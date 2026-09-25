import AVFoundation
import SwiftUI
#if os(macOS)
import AppKit
import CoreAudio
#endif

struct PreferencesView: View {
    @ObservedObject var midi: MIDIInputManager = .shared
    // Standard AppStorage properties persist directly to UserDefaults
    @AppStorage("defaultSampleRate") private var defaultSampleRate: Double = 44100.0
    @AppStorage("bufferSize") private var bufferSize: Int = 512
    @AppStorage("autoPlayOnLoad") private var autoPlayOnLoad: Bool = true
    @AppStorage("inputDeviceID") private var inputDeviceID: Int = 0
    @AppStorage("outputDeviceID") private var outputDeviceID: Int = 0
    @AppStorage("safeMode") private var safeMode = false
    @AppStorage("resamplingQuality") private var resamplingQuality = "high"
    
    // Dedicated state for Caching & Speed settings
    @AppStorage("memoryAllocationGB") private var memoryAllocationGB: Int = 6
    @AppStorage("cacheLocation") private var cacheLocation: String = "disk"
    
    // Local state for UI feedback
    @State private var cacheCleared = false
    @State private var showMIDIMappings = false
#if os(macOS)
    @State private var inputDevices: [AudioDeviceChoice] = []
    @State private var outputDevices: [AudioDeviceChoice] = []
#endif

    private func setPreference(_ key: String) {
        NotificationCenter.default.post(
            name: .audifuzzPreferenceChanged,
            object: nil,
            userInfo: ["key": key]
        )
    }

    var body: some View {
        TabView {
            // General Settings Tab
            Form {
                #if os(macOS)
                Picker("Input Device", selection: $inputDeviceID) {
                    Text("System Default").tag(0)
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onChange(of: inputDeviceID) { _ in
                    setPreference("inputDevice")
                    print("[Preferences] SET Input Device -> \(inputDeviceID)")
                }

                Picker("Output Device", selection: $outputDeviceID) {
                    Text("System Default").tag(0)
                    ForEach(outputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onChange(of: outputDeviceID) { _ in
                    setPreference("outputDevice")
                    print("[Preferences] SET Output Device -> \(outputDeviceID)")
                }
                #else
                Text("Input and output devices are managed by iOS.")
                    .foregroundColor(.secondary)
                #endif

                Divider()
                    .padding(.vertical, 4)

                Toggle("Auto-play audio when loaded", isOn: Binding(
                    get: { autoPlayOnLoad },
                    set: { newValue in
                        autoPlayOnLoad = newValue
                        setPreference("autoPlayOnLoad")
                        print("[Preferences] SET Auto-Play on Load -> \(newValue)")
                    }
                ))
                
                Picker("Buffer Size", selection: Binding(
                    get: { bufferSize },
                    set: { newValue in
                        bufferSize = newValue
                        setPreference("bufferSize")
                        print("[Preferences] SET Buffer Size -> \(newValue) samples")
                    }
                )) {
                    Text("256 samples").tag(256)
                    Text("512 samples").tag(512)
                    Text("1024 samples").tag(1024)
                }
            }
            .padding(20)
#if os(macOS)
            .onAppear(perform: refreshDevices)
#endif
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            // Audio Hardware Tab
            Form {
                Picker("Sample Rate", selection: Binding(
                    get: { defaultSampleRate },
                    set: { newValue in
                        defaultSampleRate = newValue
                        setPreference("defaultSampleRate")
                        print("[Preferences] SET Sample Rate -> \(newValue) Hz")
                    }
                )) {
                    Text("44.1 kHz").tag(44100.0)
                    Text("48.0 kHz").tag(48000.0)
                    Text("96.0 kHz").tag(96000.0)
                }
            }
            .padding(20)
            .tabItem {
                Label("Audio", systemImage: "waveform")
            }
            
            // Caching & Speed Tab
            Form {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Sample Cache Limit", selection: Binding(
                        get: { memoryAllocationGB },
                        set: { newValue in
                            memoryAllocationGB = newValue
                            setPreference("memoryAllocationGB")
                            print("[Preferences] SET Memory Allocation -> \(newValue) GB")
                        }
                    )) {
                        Text("Low (3GB)").tag(3)
                        Text("Medium (6GB)").tag(6)
                        Label("High (10GB)", systemImage: "exclamationmark.triangle.fill").tag(10)
                    }
                    
                    if memoryAllocationGB == 10 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Warning: A 10 GB cache limit may use substantial disk or temporary storage.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.default, value: memoryAllocationGB)

                Picker("Sample Cache Location", selection: Binding(
                    get: { cacheLocation },
                    set: { newValue in
                        cacheLocation = newValue
                        setPreference("cacheLocation")
                        print("[Preferences] SET Cache Location -> '\(newValue)'")
                    }
                )) {
                    Text("Disk (Slower)").tag("disk")
                    Text("RAM (Faster)").tag("ram")
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Button(cacheCleared ? "Cache Cleared!" : "Clear Sample Cache") {
                        clearTemporaryCache()
                    }
                    .disabled(cacheCleared)
                    
                    Spacer()
                    
                    Button("Reset to Defaults", role: .destructive) {
                        resetToDefaults()
                    }
                }
            }
            .padding(20)
            .tabItem {
                Label("Caching & Speed", systemImage: "clock.badge.checkmark")
            }

            Form {
                Section(header: Text("Performance")) {
                    Toggle("Safe Mode / Dropout Protection", isOn: Binding(
                        get: { safeMode },
                        set: { value in
                            safeMode = value
                            setPreference("safeMode")
                        }
                    ))
                    Text("Adds larger processing buffers to reduce crackle and dropouts under heavy CPU load.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Multiprocessing / CPU Core Limit")
                        Text("Core allocation is managed by AVAudioEngine and the operating system. Apple provides no API for an app to set its audio thread count.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Resampling Quality", selection: Binding(
                        get: { resamplingQuality },
                        set: { value in
                            resamplingQuality = value
                            setPreference("resamplingQuality")
                        }
                    )) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                        Text("Sinc (Highest)").tag("sinc")
                    }
                    Text("Controls AVAudioConverter quality when a loaded file needs sample-rate conversion.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .tabItem {
                Label("Performance", systemImage: "speedometer")
            }

            Form {
                Section(header: Text("MIDI Input")) {
                    Toggle("MIDI Input Enabled", isOn: $midi.isEnabled)

                    Picker("MIDI Input Device", selection: $midi.selectedDeviceID) {
                        Text("All Connected Devices").tag(0)
                        ForEach(midi.devices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }

                    HStack {
                        Text(midi.connectionStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Refresh") { midi.refreshDevices() }
                    }

                    Picker("MIDI Channel", selection: $midi.channel) {
                        Text("Omni (All Channels)").tag(0)
                        ForEach(1...16, id: \.self) { channel in
                            Text("Channel \(channel)").tag(channel)
                        }
                    }

                    Picker("MIDI Mode", selection: $midi.mode) {
                        Text("Selected Instrument").tag(0)
                        Text("All Enabled Instruments").tag(1)
                    }

                    if midi.mode == 0 {
                        Picker("Selected Instrument", selection: $midi.selectedInstrument) {
                            ForEach(0..<SynthRenderer.maxVoices, id: \.self) { index in
                                Text("Instrument \(index + 1)").tag(index)
                            }
                        }
                    }
                }

                Section(header: Text("MIDI Performance & Routing")) {
                    Toggle("Velocity → Volume", isOn: $midi.velocityControlsVolume)
                    Text("When off, MIDI notes use the instrument's volume dial regardless of key velocity.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Pitch Bend Range", selection: $midi.pitchBendRange) {
                        Text("±1 semitone").tag(1)
                        Text("±2 semitones").tag(2)
                        Text("±12 semitones").tag(12)
                        Text("±24 semitones").tag(24)
                    }

                    Toggle("Sustain Pedal", isOn: $midi.sustainPedalEnabled)
                    Text("CC64 holds released notes until the pedal is lifted.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("MIDI → Effects (CC Mapping)", isOn: $midi.effectsCCEnabled)
                    Text("Learn the V25's assignable knobs to control the first four Editor dials, and buttons to toggle the first four effects.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    DisclosureGroup("Alesis V25 Knob & Button Mapping", isExpanded: $showMIDIMappings) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<4, id: \.self) { index in
                                HStack {
                                    Text("Knob \(index + 1) · CC \(midi.effectKnobCCs[index])")
                                        .font(.subheadline)
                                    Spacer()
                                    Button(midi.learningEffectControl?.isButton == false && midi.learningEffectControl?.index == index ? "Move a knob…" : "Learn") {
                                        midi.learnEffectControl(index: index, isButton: false)
                                    }
                                }
                            }
                            Divider()
                            ForEach(0..<4, id: \.self) { index in
                                HStack {
                                    Text("Button \(index + 1) · CC \(midi.effectButtonCCs[index])")
                                        .font(.subheadline)
                                    Spacer()
                                    Button(midi.learningEffectControl?.isButton == true && midi.learningEffectControl?.index == index ? "Press a button…" : "Learn") {
                                        midi.learnEffectControl(index: index, isButton: true)
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .padding(20)
            .onAppear { midi.refreshDevices() }
            .tabItem {
                Label("MIDI Input", systemImage: "pianokeys")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(macOS)
        .frame(minWidth: 680, idealWidth: 820, maxWidth: .infinity,
               minHeight: 560, idealHeight: 680, maxHeight: .infinity)
        .background(SettingsWindowResizer().frame(width: 1, height: 1))
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }

#if os(macOS)
    private func refreshDevices() {
        inputDevices = AudioDeviceChoice.devices(scope: kAudioObjectPropertyScopeInput)
        outputDevices = AudioDeviceChoice.devices(scope: kAudioObjectPropertyScopeOutput)

        if inputDeviceID != 0 && !inputDevices.contains(where: { $0.id == inputDeviceID }) {
            inputDeviceID = 0
        }
        if outputDeviceID != 0 && !outputDevices.contains(where: { $0.id == outputDeviceID }) {
            outputDeviceID = 0
        }
    }
#endif

    /// Removes saved samples from the currently selected Audifuzz cache.
    private func clearTemporaryCache() {
        print("[Preferences] Initiating temporary cache clear...")
        let deletedCount = SampleStorage.clearCache()
        print("[Preferences] SUCCESS: Cleared \(deletedCount) sample file(s) from Audifuzz cache.")

        withAnimation {
            cacheCleared = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                cacheCleared = false
            }
        }
    }

    /// Resets all user preferences back to their factory settings
    private func resetToDefaults() {
        print("[Preferences] Resetting all settings to defaults...")
        defaultSampleRate = 44100.0
        bufferSize = 512
        autoPlayOnLoad = true
        inputDeviceID = 0
        outputDeviceID = 0
        memoryAllocationGB = 6
        cacheLocation = "disk"
        safeMode = false
        resamplingQuality = "high"
        midi.isEnabled = false
        midi.selectedDeviceID = 0
        midi.channel = 0
        midi.mode = 0
        midi.selectedInstrument = 0
        midi.velocityControlsVolume = true
        midi.pitchBendRange = 2
        midi.sustainPedalEnabled = true
        midi.effectsCCEnabled = false
        midi.effectKnobCCs = [20, 21, 22, 23]
        midi.effectButtonCCs = [80, 81, 82, 83]
        setPreference("all")
        print("[Preferences] SUCCESS: All preferences restored to default state.")
    }
}

#if os(macOS)
private struct SettingsWindowResizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = SettingsSizingView()
        view.applyWindowSizing()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? SettingsSizingView)?.applyWindowSizing()
    }
}

private final class SettingsSizingView: NSView {
    private let minimumWindowSize = NSSize(width: 680, height: 560)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowSizing()
    }

    func applyWindowSizing() {
        guard let window else { return }
        if !window.styleMask.contains(.resizable) { window.styleMask.insert(.resizable) }
        if window.minSize != minimumWindowSize { window.minSize = minimumWindowSize }
        window.contentView?.layoutSubtreeIfNeeded()
        configureVisibleScrollBars(in: window.contentView)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            if !window.styleMask.contains(.resizable) { window.styleMask.insert(.resizable) }
            if window.minSize != self.minimumWindowSize { window.minSize = self.minimumWindowSize }
            self.configureVisibleScrollBars(in: window.contentView)
        }
    }

    private func configureVisibleScrollBars(in view: NSView?) {
        guard let view else { return }
        if let scrollView = view as? NSScrollView, scrollView.hasVerticalScroller {
            if scrollView.scrollerStyle != .legacy { scrollView.scrollerStyle = .legacy }
            if scrollView.autohidesScrollers { scrollView.autohidesScrollers = false }
        }
        for child in view.subviews {
            configureVisibleScrollBars(in: child)
        }
    }
}
#endif

#if os(macOS)
private struct AudioDeviceChoice: Identifiable, Hashable {
    let id: Int
    let name: String

    static func devices(scope: AudioObjectPropertyScope) -> [AudioDeviceChoice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasChannels(deviceID: deviceID, scope: scope) else { return nil }
            return AudioDeviceChoice(id: Int(deviceID), name: name(for: deviceID))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func hasChannels(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, buffer) == noErr else { return false }
        let audioBufferList = buffer.assumingMemoryBound(to: AudioBufferList.self).pointee
        return audioBufferList.mNumberBuffers > 0 && audioBufferList.mBuffers.mNumberChannels > 0
    }

    private static func name(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name) == noErr,
              let name else { return "Unknown Device" }
        return name.takeUnretainedValue() as String
    }
}
#endif

// Xcode Canvas Preview setup
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView(midi: MIDIInputManager())
    }
}
