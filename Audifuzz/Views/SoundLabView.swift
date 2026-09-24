import SwiftUI

/// Second tab: build a sound from stacked waves,
/// then save it or send it to the Editor tab as a sample.
struct SoundLabView: View {
    @ObservedObject var lab: SoundLabEngine
    var onUseSample: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Sound Lab").font(.largeTitle.bold())
                controls

                ForEach(Array(lab.voices.enumerated()), id: \.element.id) { index, voice in
                    VoiceCardView(
                        voice: lab.binding(for: voice.id),
                        index: index,
                        canRemove: lab.voices.count > 1,
                        onRemove: { lab.removeVoice(voice.id) })
                }

                Button("Add instrument") { lab.addVoice() }
                    .buttonStyle(.bordered)
                    .disabled(lab.voices.count >= SynthRenderer.maxVoices)

                samplesList
            }
            .padding()
        }
        .onAppear { lab.refreshSamples() }
        .onDisappear { lab.stopPreview() }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                Button(lab.isPlaying ? "Stop" : "Play") { lab.togglePlay() }
                Button("Save Sample") { lab.saveSample() }
                    .disabled(lab.isSaving)
                Dial(title: "Length", value: $lab.duration, range: 1...10, unit: " s", size: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let message = lab.statusMessage {
                Text(message).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private var samplesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved samples").font(.headline)
            if lab.samples.isEmpty {
                Text("Nothing saved yet.").font(.footnote).foregroundColor(.secondary)
            }
            ForEach(lab.samples, id: \.self) { url in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.footnote).lineLimit(1)
                        if BuiltInSoundLibrary.isBuiltIn(url) {
                            Text("Included starter sound")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    
                    Button("Use in Editor") {
                        // 1. Stop SoundLab's preview engine FIRST so it releases hardware output
                        lab.stopPreview()
                        
                        // 2. Ensure URL is correctly formatted for disk access
                        let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path)
                        
                        // 3. Defer loading and tab navigation to the next runloop frame
                        DispatchQueue.main.async {
                            onUseSample(fileURL)
                        }
                    }

                    Button { lab.deleteSample(url) } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.borderless)
            }
        }
        .card()
    }
}

struct EqualizerView: View {
    @ObservedObject var lab: SoundLabEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 54, height: 54)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Equalizer").font(.largeTitle.bold())
                        Text("Shape the tone of your Sound Lab instruments across five bands.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                EqualizerCardView(lab: lab)
            }
            .padding()
        }
    }
}

struct VoiceCardView: View {
    @Binding var voice: Voice
    let index: Int
    let canRemove: Bool
    let onRemove: () -> Void

    private func panText(_ v: Float) -> String {
        if abs(v) < 0.02 { return "Center" }
        return v < 0 ? "L \(Int(-v * 100))%" : "R \(Int(v * 100))%"
    }

    private func logSettledVoice() {
        print("[SoundLabEngine] Voice '\(voice.id)' settled: Freq \(Int(voice.frequency.rounded())) Hz, Volume \(Int(voice.volume * 100))%, Pan \(String(format: "%.2f", voice.pan))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Instrument \(index + 1)", isOn: $voice.enabled)
                    .font(.headline)
                Spacer()
                if canRemove {
                    Button { onRemove() } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }

            Picker("Shape", selection: $voice.wave) {
                ForEach(Wave.allCases) { w in
                    Text(w.label).tag(w)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                Dial(title: "Pitch", value: $voice.frequency, range: 20...5000, isLog: true, size: 64,
                     format: { "\(Int($0.rounded())) Hz\n\(noteName($0))" },
                     onEditingEnded: logSettledVoice)
                Dial(title: "Volume", value: $voice.volume, range: 0...1,
                     format: { "\(Int($0 * 100))%" },
                     onEditingEnded: logSettledVoice)
                 Dial(title: "Ear", value: $voice.pan, range: -1...1, format: panText,
                     onEditingEnded: logSettledVoice)
                Dial(title: "Sweep", value: $voice.sweep, range: 0...1,
                     format: { "\(Int($0 * 100))%" },
                     onEditingEnded: logSettledVoice)
                 Dial(title: "Sweep speed", value: $voice.sweepRate, range: 0.1...10, unit: " Hz",
                     onEditingEnded: logSettledVoice)
            }
        }
        .card()
    }
}

struct EqualizerCardView: View {
    @ObservedObject var lab: SoundLabEngine

    private func logSettledEQ() {
        let gains = lab.eqGains.map { String(format: "%+.1f", $0) }.joined(separator: ", ")
        print("[SoundLabEngine] EQ settled: [\(gains)] dB")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equalizer").font(.headline)

            EQResponseGraph(
                gains: $lab.eqGains,
                waveform: lab.waveform,
                onEditingEnded: logSettledEQ
            )
        }
        .card()
    }
}

private struct EQGraphPlot: View {
    @Binding var gains: [Float]
    let waveform: [Float]
    let frequencies: [Double]
    let frequencyLabels: [(Double, String)]
    let gainLines: [Float]
    let maximumGain: CGFloat
    var onEditingEnded: (() -> Void)?

    @State private var activeBand: Int?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = max(CGFloat(1), geometry.size.height - 24)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let plotHeight = max(CGFloat(1), size.height - 24)
                    context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(.black.opacity(0.18)))

                    for gain in gainLines {
                        var path = Path()
                        let y = yPosition(for: gain, height: plotHeight)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                        let opacity = gain == 0 ? 0.5 : 0.2
                        context.stroke(path, with: .color(.secondary.opacity(opacity)), lineWidth: gain == 0 ? 1 : 0.5)
                    }

                    for frequency in frequencyLabels {
                        var path = Path()
                        let x = xPosition(for: frequency.0, width: width)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: plotHeight))
                        context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)
                    }

                    context.fill(responseArea(width: width, height: plotHeight), with: .color(.accentColor.opacity(0.14)))
                    context.stroke(responsePath(width: width, height: plotHeight), with: .color(.accentColor), lineWidth: 2)
                    context.stroke(waveformPath(width: width, height: plotHeight), with: .color(.white.opacity(0.65)), lineWidth: 1)

                    for (index, frequency) in frequencies.enumerated() {
                        let point = CGPoint(x: xPosition(for: frequency, width: width), y: yPosition(for: gain(at: index), height: plotHeight))
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.accentColor))
                    }
                }

                ForEach(frequencyLabels, id: \.0) { frequency, label in
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(x: xPosition(for: frequency, width: width), y: height + 12)
                }

                Text("+18").font(.caption2).foregroundColor(.secondary).position(x: 18, y: 8)
                Text("0").font(.caption2).foregroundColor(.secondary).position(x: 10, y: height / 2)
                Text("-18").font(.caption2).foregroundColor(.secondary).position(x: 18, y: height - 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(graphGesture(width: width, height: height))
        }
    }

    private func graphGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if activeBand == nil {
                    activeBand = nearestBand(to: gesture.location.x, width: width)
                }
                guard let activeBand, gains.indices.contains(activeBand) else { return }
                let clampedY = min(max(CGFloat(0), gesture.location.y), height)
                gains[activeBand] = gainValue(for: clampedY, height: height)
            }
            .onEnded { _ in
                activeBand = nil
                onEditingEnded?()
            }
    }

    private func responsePath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            for sample in 0...96 {
                let fraction = Double(sample) / 96
                let frequency = 20 * pow(1000, fraction)
                let point = CGPoint(x: xPosition(for: frequency, width: width), y: yPosition(for: interpolatedGain(at: frequency), height: height))
                sample == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    private func responseArea(width: CGFloat, height: CGFloat) -> Path {
        var path = responsePath(width: width, height: height)
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }

    private func waveformPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            guard waveform.count > 1 else { return }
            for index in waveform.indices {
                let x = CGFloat(index) / CGFloat(waveform.count - 1) * width
                let y = height / 2 - max(-1, min(1, CGFloat(waveform[index]))) * height * 0.22
                index == waveform.startIndex ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }

    private func xPosition(for frequency: Double, width: CGFloat) -> CGFloat {
        CGFloat(log10(max(20, min(20000, frequency)) / 20) / log10(1000)) * width
    }

    private func yPosition(for gain: Float, height: CGFloat) -> CGFloat {
        height / 2 - CGFloat(max(-maximumGain, min(maximumGain, CGFloat(gain)))) / maximumGain * height / 2
    }

    private func gainValue(for y: CGFloat, height: CGFloat) -> Float {
        Float(max(-maximumGain, min(maximumGain, (height / 2 - y) / (height / 2) * maximumGain)))
    }

    private func nearestBand(to x: CGFloat, width: CGFloat) -> Int {
        frequencies.indices.min { first, second in
            abs(xPosition(for: frequencies[first], width: width) - x) < abs(xPosition(for: frequencies[second], width: width) - x)
        } ?? 0
    }

    private func gain(at index: Int) -> Float {
        gains.indices.contains(index) ? gains[index] : 0
    }

    private func interpolatedGain(at frequency: Double) -> Float {
        if frequency <= frequencies[0] { return gain(at: 0) }
        if frequency >= frequencies[frequencies.count - 1] { return gain(at: frequencies.count - 1) }
        for index in 0..<(frequencies.count - 1) {
            let lower = frequencies[index]
            let upper = frequencies[index + 1]
            if frequency <= upper {
                let fraction = (log(frequency) - log(lower)) / (log(upper) - log(lower))
                return gain(at: index) + Float(fraction) * (gain(at: index + 1) - gain(at: index))
            }
        }
        return 0
    }
}

struct EQResponseGraph: View {
    @Binding var gains: [Float]
    let waveform: [Float]
    var onEditingEnded: (() -> Void)? = nil

    @State private var activeBand: Int?

    private let frequencies: [Double] = [60, 250, 1000, 4000, 12000]
    private let frequencyLabels = [(20.0, "20"), (100.0, "100"), (1000.0, "1k"), (10000.0, "10k"), (20000.0, "20k")]
    private let gainLines: [Float] = [-18, -9, 0, 9, 18]
    private let maximumGain: CGFloat = 18

    var body: some View {
        EQGraphPlot(
            gains: $gains,
            waveform: waveform,
            frequencies: frequencies,
            frequencyLabels: frequencyLabels,
            gainLines: gainLines,
            maximumGain: maximumGain,
            onEditingEnded: onEditingEnded
        )
        .frame(height: 172)
        .drawingGroup()
    }

    private func responsePath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let sampleCount = 96
            for sample in 0...sampleCount {
                let fraction = Double(sample) / Double(sampleCount)
                let frequency = 20 * pow(1000, fraction)
                let point = CGPoint(
                    x: xPosition(for: frequency, width: width),
                    y: yPosition(for: interpolatedGain(at: frequency), height: height)
                )
                if sample == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func responseArea(width: CGFloat, height: CGFloat) -> Path {
        var path = responsePath(width: width, height: height)
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        return path
    }

    private func waveformPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            guard waveform.count > 1 else { return }
            let amplitude = height * 0.22
            for index in waveform.indices {
                let x = CGFloat(index) / CGFloat(waveform.count - 1) * width
                let sample = max(-1, min(1, CGFloat(waveform[index])))
                let y = height / 2 - sample * amplitude
                if index == waveform.startIndex {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func xPosition(for frequency: Double, width: CGFloat) -> CGFloat {
        CGFloat(log10(max(20, min(20000, frequency)) / 20) / log10(1000)) * width
    }

    private func yPosition(for gain: Float, height: CGFloat) -> CGFloat {
        height / 2 - CGFloat(max(-maximumGain, min(maximumGain, CGFloat(gain)))) / maximumGain * height / 2
    }

    private func gainValue(for y: CGFloat, height: CGFloat) -> Float {
        Float(max(-maximumGain, min(maximumGain, (height / 2 - y) / (height / 2) * maximumGain)))
    }

    private func nearestBand(to x: CGFloat, width: CGFloat) -> Int {
        frequencies.indices.min { first, second in
            abs(xPosition(for: frequencies[first], width: width) - x) < abs(xPosition(for: frequencies[second], width: width) - x)
        } ?? 0
    }

    private func gain(at index: Int) -> Float {
        gains.indices.contains(index) ? gains[index] : 0
    }

    private func interpolatedGain(at frequency: Double) -> Float {
        guard !frequencies.isEmpty else { return 0 }
        if frequency <= frequencies[0] { return gain(at: 0) }
        if frequency >= frequencies[frequencies.count - 1] { return gain(at: frequencies.count - 1) }

        for index in 0..<(frequencies.count - 1) {
            let lower = frequencies[index]
            let upper = frequencies[index + 1]
            guard frequency <= upper else { continue }
            let fraction = (log(frequency) - log(lower)) / (log(upper) - log(lower))
            return gain(at: index) + Float(fraction) * (gain(at: index + 1) - gain(at: index))
        }
        return 0
    }
}
