#if os(macOS)
import AppKit
import CoreAudio
import Darwin
import SwiftUI
import UniformTypeIdentifiers

private struct BenchmarkProfile: Identifiable {
    let id: Int
    let sampleRate: Double
    let bufferSize: Int

    var name: String { "\(Int(sampleRate / 1000)) kHz · \(bufferSize) frames" }
}

private struct BenchmarkSample {
    let elapsed: Double
    let profile: String
    let cpuPercent: Double
    let residentMB: Double
    let outputRMS: Double
    let activeNoteCount: Int
    let cutCount: Int
}

private struct BenchmarkDip {
    let elapsed: Double
    let profile: String
    let level: Double
    let precedingLevel: Double
}

struct BenchmarkWizardView: View {
    @ObservedObject var midi: MIDIInputManager
    @ObservedObject var lab: SoundLabEngine
    @Binding var sampleRate: Double
    @Binding var bufferSize: Int
    @Binding var safeMode: Bool
    @Binding var resamplingQuality: String

    @Environment(\.presentationMode) private var presentationMode
    @State private var isRunning = false
    @State private var isComplete = false
    @State private var profileIndex = 0
    @State private var runStartedAt: TimeInterval = 0
    @State private var profileStartedAt: TimeInterval = 0
    @State private var samples: [BenchmarkSample] = []
    @State private var dips: [BenchmarkDip] = []
    @State private var lowLevelTicks = 0
    @State private var recoveredTicks = 0
    @State private var levelBaseline = 0.0
    @State private var lastCPUTime: Double = 0
    @State private var lastSampleTime: TimeInterval = 0
    @State private var isExporting = false
    @State private var originalSettings: SettingsSnapshot?

    private let profileDuration: TimeInterval = 10
    private let settleDuration: TimeInterval = 2
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let profiles: [BenchmarkProfile] = [
        BenchmarkProfile(id: 0, sampleRate: 44100, bufferSize: 256),
        BenchmarkProfile(id: 1, sampleRate: 44100, bufferSize: 512),
        BenchmarkProfile(id: 2, sampleRate: 48000, bufferSize: 256),
        BenchmarkProfile(id: 3, sampleRate: 48000, bufferSize: 512),
        BenchmarkProfile(id: 4, sampleRate: 48000, bufferSize: 1024),
        BenchmarkProfile(id: 5, sampleRate: 96000, bufferSize: 512)
    ]

    private struct SettingsSnapshot {
        let sampleRate: Double
        let bufferSize: Int
        let safeMode: Bool
        let resamplingQuality: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Performance Benchmark").font(.title2.bold())
                    Text(isComplete ? "Run complete" : (isRunning ? "Profile \(profileIndex + 1) of \(profiles.count)" : "Guided system and audio diagnostics"))
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { presentationMode.wrappedValue.dismiss() }
                    .disabled(isRunning)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !isRunning && !isComplete {
                        introduction
                    } else {
                        graphs
                        if isRunning { activeTrialCard }
                        if isComplete { resultsSummary }
                    }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }

            Divider()
            HStack {
                if isComplete {
                    Button("Export Detailed Markdown…") { isExporting = true }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Run Again") { resetRun() }
                } else if isRunning {
                    Text("Keep one MIDI key held through each profile. Changes settle for 2 seconds before measurements.")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Stop & Restore Settings", role: .destructive) { stopAndRestore() }
                } else {
                    Text("Estimated run time: about 1 minute").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Start Benchmark") { startBenchmark() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!midi.isEnabled || midi.activeNotes.isEmpty)
                }
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 640)
        .onReceive(timer) { _ in sampleIfNeeded() }
        .onDisappear { if isRunning { stopAndRestore() } }
        .fileExporter(isPresented: $isExporting,
                      document: BenchmarkMarkdownDocument(text: markdownReport),
                      contentType: .plainText,
                      defaultFilename: "Audifuzz-Performance-Benchmark.md") { _ in }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Hold a steady MIDI note during the run", systemImage: "pianokeys")
                .font(.headline)
            Text("The wizard applies six sample-rate and buffer-size profiles to the live audio engine. It samples Audifuzz process CPU, resident memory, and SynthSpace output level. Hold one key for the full run; brief near-silent gaps after the sound has stabilized are recorded as possible audio cuts.")
                .foregroundColor(.secondary)
            Text("The MIDI sampler uses its own AVAudioEngine at the current output device rate. These profiles exercise the Editor engine settings while the MIDI note is held, so the cut counter measures cross-engine stability; it does not force the MIDI sampler to render at a different hardware sample rate.")
                .font(.caption).foregroundColor(.secondary)
            Text("For a representative settings comparison, keep Editor audio playing during the run as well as holding the MIDI key. Without active Editor audio or microphone input, the run still records system and MIDI output data, but it cannot fully exercise the Editor buffer path.")
                .font(.caption).foregroundColor(.secondary)
            HStack(spacing: 10) {
                Label(midi.isEnabled ? midi.currentDeviceName : "MIDI input is off", systemImage: midi.isEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(midi.isEnabled ? .green : .orange)
                Spacer()
                Text("Current instrument: \(lab.midiInstrumentOptions.indices.contains(midi.selectedInstrument) ? lab.midiInstrumentOptions[midi.selectedInstrument] : "Unknown")")
                    .foregroundColor(.secondary)
            }
            .padding().card()
            VStack(alignment: .leading, spacing: 8) {
                Text("What gets measured").font(.headline)
                Label("CPU: process usage, normalized to all available cores", systemImage: "cpu")
                Label("RAM: Audifuzz resident memory", systemImage: "memorychip")
                Label("Audio cuts: measured SynthSpace signal drops while a MIDI note is held", systemImage: "waveform.path")
                Label("Power draw: unavailable through macOS public per-app APIs", systemImage: "bolt.slash")
                    .foregroundColor(.secondary)
            }
            .padding().card()
            Text("The original sample rate, buffer size, Safe Mode, and resampling quality are restored when the run ends or is stopped. The Editor may briefly restart as each profile is applied.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var activeTrialCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform")
                Text(profiles[profileIndex].name).font(.headline)
                Spacer()
                Text("\(max(0, Int(profileDuration - (ProcessInfo.processInfo.systemUptime - profileStartedAt))))s")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: min(1, max(0, (ProcessInfo.processInfo.systemUptime - profileStartedAt) / profileDuration)))
            Text(midi.activeNotes.isEmpty ? "No held MIDI note detected. Start holding one key now." : "Note detected. Keep holding the same key steadily.")
                .font(.caption).foregroundColor(midi.activeNotes.isEmpty ? .orange : .secondary)
            HStack {
                Label("Possible cuts: \(dips.count)", systemImage: "waveform.path.ecg")
                Spacer()
                Text("Settling" + (ProcessInfo.processInfo.systemUptime - profileStartedAt >= settleDuration ? " complete" : "…"))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding().card()
    }

    private var graphs: some View {
        VStack(spacing: 12) {
            BenchmarkLineChart(title: "CPU Usage", subtitle: "% of available cores", values: samples.map(\.cpuPercent), suffix: "%", color: .cyan)
            BenchmarkLineChart(title: "RAM", subtitle: "Audifuzz resident memory", values: samples.map(\.residentMB), suffix: " MB", color: .purple)
            BenchmarkLineChart(title: "Power Draw", subtitle: "Not exposed by macOS public per-app APIs", values: [], suffix: "", color: .orange, unavailable: true)
            BenchmarkLineChart(title: "Performance Dips", subtitle: "Cumulative possible audio cuts during held note", values: samples.map { Double($0.cutCount) }, suffix: "", color: .pink)
        }
    }

    private var resultsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Benchmark results ready", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundColor(.green)
            Text("\(samples.count) telemetry samples · \(profiles.count) profiles · \(dips.count) possible signal cuts recorded")
                .foregroundColor(.secondary)
            Text("Export the Markdown report for profile-by-profile statistics, environment details, cut timestamps, and the full sampled data table.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding().card()
    }

    private func startBenchmark() {
        originalSettings = SettingsSnapshot(sampleRate: sampleRate, bufferSize: bufferSize,
                                            safeMode: safeMode, resamplingQuality: resamplingQuality)
        samples.removeAll()
        dips.removeAll()
        profileIndex = 0
        isComplete = false
        isRunning = true
        runStartedAt = ProcessInfo.processInfo.systemUptime
        applyProfile(profiles[0])
        profileStartedAt = ProcessInfo.processInfo.systemUptime
        lastCPUTime = processCPUSeconds()
        lastSampleTime = profileStartedAt
        lowLevelTicks = 0
        recoveredTicks = 0
        levelBaseline = 0
    }

    private func sampleIfNeeded() {
        guard isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - profileStartedAt >= settleDuration else { return }
        let elapsed = now - runStartedAt
        let rms = currentOutputRMS()
        let cpuTime = processCPUSeconds()
        let interval = max(0.001, now - lastSampleTime)
        let cpu = max(0, min(100, ((cpuTime - lastCPUTime) / interval) * 100 / Double(max(1, ProcessInfo.processInfo.activeProcessorCount))))
        lastCPUTime = cpuTime
        lastSampleTime = now

        if !midi.activeNotes.isEmpty {
            if rms > 0.006 {
                levelBaseline = levelBaseline == 0 ? rms : (levelBaseline * 0.92 + rms * 0.08)
                recoveredTicks += 1
                if recoveredTicks >= 2 { lowLevelTicks = 0 }
            } else if levelBaseline > 0 && recoveredTicks >= 2 {
                lowLevelTicks += 1
                if lowLevelTicks == 3 {
                    dips.append(BenchmarkDip(elapsed: elapsed, profile: profiles[profileIndex].name,
                                             level: rms, precedingLevel: levelBaseline))
                }
                if lowLevelTicks > 3 { lowLevelTicks = 3 }
            }
        } else {
            lowLevelTicks = 0
            recoveredTicks = 0
        }

        if elapsed >= profileStartedAt - runStartedAt + settleDuration {
            samples.append(BenchmarkSample(elapsed: elapsed, profile: profiles[profileIndex].name,
                                           cpuPercent: cpu, residentMB: processResidentMB(), outputRMS: rms,
                                           activeNoteCount: midi.activeNotes.count, cutCount: dips.count))
        }

        if now - profileStartedAt >= profileDuration {
            profileIndex += 1
            if profileIndex >= profiles.count {
                isRunning = false
                isComplete = true
                restoreSettings()
            } else {
                applyProfile(profiles[profileIndex])
                profileStartedAt = now
                lastCPUTime = processCPUSeconds()
                lastSampleTime = now
                lowLevelTicks = 0
                recoveredTicks = 0
                levelBaseline = 0
            }
        }
    }

    private func currentOutputRMS() -> Double {
        let points = lab.waveform
        guard !points.isEmpty else { return 0 }
        let meanSquare = points.reduce(0.0) { $0 + Double($1 * $1) } / Double(points.count)
        return sqrt(meanSquare)
    }

    private func applyProfile(_ profile: BenchmarkProfile) {
        sampleRate = profile.sampleRate
        bufferSize = profile.bufferSize
        postPreference("defaultSampleRate")
        postPreference("bufferSize")
    }

    private func postPreference(_ key: String) {
        NotificationCenter.default.post(name: .audifuzzPreferenceChanged, object: nil, userInfo: ["key": key])
    }

    private func restoreSettings() {
        guard let originalSettings else { return }
        sampleRate = originalSettings.sampleRate
        bufferSize = originalSettings.bufferSize
        safeMode = originalSettings.safeMode
        resamplingQuality = originalSettings.resamplingQuality
        postPreference("all")
        self.originalSettings = nil
    }

    private func stopAndRestore() {
        isRunning = false
        restoreSettings()
    }

    private func resetRun() {
        samples.removeAll()
        dips.removeAll()
        profileIndex = 0
        isComplete = false
    }

    private var markdownReport: String {
        let meanCPU = samples.isEmpty ? 0 : samples.map(\.cpuPercent).reduce(0, +) / Double(samples.count)
        let peakCPU = samples.map(\.cpuPercent).max() ?? 0
        let meanRAM = samples.isEmpty ? 0 : samples.map(\.residentMB).reduce(0, +) / Double(samples.count)
        let peakRAM = samples.map(\.residentMB).max() ?? 0
        var lines = [
            "# Audifuzz Performance Benchmark",
            "",
            "## Run summary",
            "",
            "- Captured: \(Date().formatted(date: .complete, time: .complete))",
            "- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "- CPU: \(cpuModel())",
            "- Logical processors: \(ProcessInfo.processInfo.activeProcessorCount)",
            "- Physical memory: \(ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))",
            "- MIDI device: \(midi.currentDeviceName)",
            "- MIDI input enabled: \(midi.isEnabled)",
            "- MIDI instrument: \(selectedInstrumentName)",
            "- Trial duration: \(Int(profileDuration)) seconds per profile (first \(Int(settleDuration)) seconds excluded for settling)",
            "- Profiles completed: \(min(profiles.count, profileIndex + (isComplete ? 0 : 1))) / \(profiles.count)",
            "- Telemetry samples: \(samples.count)",
            "- Detected possible audio cuts: \(dips.count)",
            "- CPU average / peak: \(String(format: "%.2f", meanCPU))% / \(String(format: "%.2f", peakCPU))% of total available CPU capacity",
            "- RAM average / peak: \(String(format: "%.1f", meanRAM)) MB / \(String(format: "%.1f", peakRAM)) MB resident",
            "- Power draw: Not available. macOS does not expose a supported public API for per-app instantaneous wattage. Xcode Instruments Energy Log can provide a separate qualitative Energy Impact trace, but it does not yield per-app watts for this report.",
            "",
            "## Test method and interpretation",
            "",
            "Audifuzz applied the Editor audio settings shown for each profile and sampled process CPU, process resident memory, and the SynthSpace sampler's output waveform at approximately 4 Hz. The MIDI sampler runs in its own AVAudioEngine at the output device's hardware rate. Holding a MIDI note while Editor settings are varied measures whole-app resource use and cross-engine stability; it does not change the MIDI engine's hardware sample rate. The same MIDI key should be held continuously. Each profile's first \(Int(settleDuration)) seconds were excluded to avoid counting engine reconfiguration as an audio cut.",
            "",
            "A possible cut is counted when MIDI still reports a held key and the measured SynthSpace waveform RMS stays below 0.006 for three consecutive samples, after a stable signal baseline above 0.006 was observed. This is a signal-gap indicator, not a guaranteed audible-click detector; silence caused by releasing the key, changing instruments, or a sampler failure can affect the count.",
            "",
            "CPU usage is normalized against all logical processors (100% represents all reported CPU capacity). Resident memory is the process footprint snapshot reported by Mach task information. Safe Mode and resampling quality remain at their original values for every profile. Power draw is deliberately left unmeasured rather than estimated. Xcode Instruments Energy Log can record qualitative Energy Impact separately, but its data is not automatically available to an app or expressed as per-app watts.",
            "",
            "## Profile summary",
            "",
            "| Profile | Sample rate | Buffer | CPU avg | CPU peak | RAM avg | RAM peak | Possible cuts | Samples |",
            "|:--|--:|--:|--:|--:|--:|--:|--:|--:|"
        ]
        for profile in profiles {
            let rows = samples.filter { $0.profile == profile.name }
            guard !rows.isEmpty else { continue }
            let cpuAverage = rows.map(\.cpuPercent).reduce(0, +) / Double(rows.count)
            let ramAverage = rows.map(\.residentMB).reduce(0, +) / Double(rows.count)
            let cutTotal = dips.filter { $0.profile == profile.name }.count
            lines.append("| \(profile.name) | \(Int(profile.sampleRate)) Hz | \(profile.bufferSize) frames | \(String(format: "%.2f", cpuAverage))% | \(String(format: "%.2f", rows.map(\.cpuPercent).max() ?? 0))% | \(String(format: "%.1f", ramAverage)) MB | \(String(format: "%.1f", rows.map(\.residentMB).max() ?? 0)) MB | \(cutTotal) | \(rows.count) |")
        }
        lines += ["", "## Possible audio-cut events", "", "| Elapsed | Profile | Signal RMS | Prior baseline RMS |", "|--:|:--|--:|--:|"]
        if dips.isEmpty {
            lines.append("| — | No possible cuts detected | — | — |")
        } else {
            for dip in dips {
                lines.append("| \(String(format: "%.2f", dip.elapsed)) s | \(dip.profile) | \(String(format: "%.5f", dip.level)) | \(String(format: "%.5f", dip.precedingLevel)) |")
            }
        }
        lines += ["", "## Full telemetry", "", "| Elapsed | Profile | CPU % | Resident MB | Waveform RMS | Held MIDI notes | Cumulative possible cuts |", "|--:|:--|--:|--:|--:|--:|--:|"]
        for sample in samples {
            lines.append("| \(String(format: "%.2f", sample.elapsed)) s | \(sample.profile) | \(String(format: "%.2f", sample.cpuPercent)) | \(String(format: "%.1f", sample.residentMB)) | \(String(format: "%.5f", sample.outputRMS)) | \(sample.activeNoteCount) | \(sample.cutCount) |")
        }
        lines += ["", "## Settings after run", "", "Original values were restored after the benchmark:", "", "- Sample rate: \(Int(sampleRate)) Hz", "- Buffer size: \(bufferSize) frames", "- Safe Mode: \(safeMode ? "On" : "Off")", "- Resampling quality: \(resamplingQuality)", ""]
        return lines.joined(separator: "\n")
    }

    private var selectedInstrumentName: String {
        lab.midiInstrumentOptions.indices.contains(midi.selectedInstrument) ? lab.midiInstrumentOptions[midi.selectedInstrument] : "Unknown"
    }

    private func processCPUSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private func processResidentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    private func cpuModel() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 1 else { return "Unavailable" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "Unavailable" }
        return String(cString: buffer)
    }
}

private struct BenchmarkLineChart: View {
    let title: String
    let subtitle: String
    let values: [Double]
    let suffix: String
    let color: Color
    var unavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            GeometryReader { geometry in
                let maxValue = max(values.max() ?? 1, 1)
                ZStack {
                    Path { path in
                        for index in 1...3 {
                            let y = geometry.size.height * CGFloat(index) / 4
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                    if !unavailable && values.count > 1 {
                        Path { path in
                            for (index, value) in values.enumerated() {
                                let x = CGFloat(index) / CGFloat(values.count - 1) * geometry.size.width
                                let y = geometry.size.height * (1 - CGFloat(value / maxValue))
                                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if unavailable {
                        Text("Unavailable through macOS public APIs")
                            .font(.caption).foregroundColor(.secondary)
                    } else if values.isEmpty {
                        Text("Measurements will appear during the run")
                            .font(.caption).foregroundColor(.secondary)
                    } else {
                        VStack {
                            HStack { Spacer(); Text("\(String(format: "%.1f", values.last ?? 0))\(suffix)").font(.caption.monospacedDigit()).foregroundColor(color) }
                            Spacer()
                        }
                        .padding(5)
                    }
                }
            }
            .frame(height: 74)
            .drawingGroup()
        }
        .padding(12)
        .card()
    }
}

private struct BenchmarkMarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
#endif
