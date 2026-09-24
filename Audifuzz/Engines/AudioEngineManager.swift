import AVFoundation
import SwiftUI
#if os(macOS)
import CoreAudio
#endif

extension Notification.Name {
    static let audifuzzPreferenceChanged = Notification.Name("AudifuzzPreferenceChanged")
}

/// Editor audio. Two engines on purpose:
///
/// Output engine (never touches the mic, so it can't hit the macOS duplex crash):
///   file player ─┐
///                ├─> sourceMixer -> effect 1 -> ... -> effect N -> [spatializer] -> main mixer -> speakers
///   mic player ──┘
///
/// Mic engine (input only): microphone -> tap -> copies of each buffer are queued on `micPlayer`.
final class AudioEngineManager: ObservableObject {
    enum Source: String, CaseIterable, Identifiable {
        case file = "File"
        case mic = "Mic"
        var id: String { rawValue }
    }

    @Published private(set) var effects: [EffectModule] {
        didSet {
            print("[AudioEngineManager] Effects array mutated. Total active effects: \(effects.count)")
        }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var fileName: String?
    @Published private(set) var isMicLive = false
    @Published private(set) var isRecording = false
    @Published var errorMessage: String? {
        didSet {
            if let msg = errorMessage {
                print("[ERROR] AudioEngineManager error reported: \(msg)")
            }
        }
    }
    let spatial = SpatialStage()

    var source: Source { isMicLive ? .mic : .file }

    // MARK: - Preferences Reading
    private var userSampleRate: Double {
        let rate = UserDefaults.standard.double(forKey: "defaultSampleRate")
        let resolved = rate > 0 ? rate : 44100.0
        print("[Preferences] Sample rate requested: \(resolved) Hz")
        return resolved
    }

    private var userBufferSize: AVAudioFrameCount {
        let size = UserDefaults.standard.integer(forKey: "bufferSize")
        let resolved = size > 0 ? AVAudioFrameCount(size) : 512
        print("[Preferences] Buffer size requested: \(resolved) frames")
        return resolved
    }

    private var preferredInputDeviceID: UInt32 {
        let id = UserDefaults.standard.integer(forKey: "inputDeviceID")
        return id > 0 ? UInt32(id) : 0
    }

    private var preferredOutputDeviceID: UInt32 {
        let id = UserDefaults.standard.integer(forKey: "outputDeviceID")
        return id > 0 ? UInt32(id) : 0
    }

    private var autoPlayOnLoad: Bool {
        if UserDefaults.standard.object(forKey: "autoPlayOnLoad") == nil { return true }
        let enabled = UserDefaults.standard.bool(forKey: "autoPlayOnLoad")
        print("[Preferences] Auto-play on load: \(enabled)")
        return enabled
    }

    // Output engine
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let micPlayer = AVAudioPlayerNode()
    private let sourceMixer = AVAudioMixerNode()
    private var graphFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) ?? AVAudioFormat()
    private var file: AVAudioFile?
    private var scopedURL: URL?
    private var playbackID = 0
    private var micConnected = false
    private var recordingURL: URL?

    // Mic engine (input only)
    private let micEngine = AVAudioEngine()
    private var micFormat: AVAudioFormat?

    // Shared with the mic tap thread, so guarded by a lock.
    private let micLock = NSLock()
    private var pendingMicBuffers = 0
    private var micGeneration = 0
    private var micPlayerReady = false
    private var recordingFile: AVAudioFile?
    private var preferenceObserver: NSObjectProtocol?

    init() {
        print("[AudioEngineManager] Initializing audio engine and effect modules...")
        effects = [
            OverdriveEffect(),
            BitCrushEffect(),
            FilterEffect(),
            PitchEffect(),
            DelayEffect(),
            ReverbEffect()
        ]
        engine.attach(player)
        engine.attach(micPlayer)
        engine.attach(sourceMixer)
        engine.attach(spatial.mixer)
        engine.attach(spatial.environment)
        effects.forEach { engine.attach($0.unit) }
        applyPreferredDevices()
        spatial.onRouteChange = { [weak self] in
            guard let self = self else { return }
            print("[SpatialStage] Route configuration changed. Rebuilding chain...")
            if self.isPlaying { self.stop() }
            self.rebuildChain()
        }
        refreshGraphFormat()
        rebuildChain()

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            print("[AudioEngine] Configuration change detected on main engine. Restarting...")
            self?.restartEngine()
        }

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: micEngine, queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isMicLive else { return }
            print("[AudioEngine] Configuration change detected on mic engine.")
            self.stopMic()
            self.errorMessage = "The microphone changed. Tap Mic to start it again."
        }

        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .audifuzzPreferenceChanged, object: nil, queue: .main
        ) { [weak self] notification in
            let key = notification.userInfo?["key"] as? String
            self?.applyPreferenceChange(key)
        }
        
        print("[AudioEngineManager] Initialization complete. Engine ready.")
    }

    deinit {
        if let observer = preferenceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func applyPreferenceChange(_ key: String?) {
        switch key {
        case "defaultSampleRate":
            if file != nil || isMicLive {
                restartEngine()
            } else {
                refreshGraphFormat()
            }
        case "bufferSize":
            if isMicLive {
                installMicTap()
            }
            if file != nil {
                restartEngine()
            }
        case "inputDevice":
            if isMicLive {
                stopMic()
                startMic()
            } else {
                applyPreferredDevices()
            }
        case "outputDevice":
            restartEngine()
        default:
            break
        }
    }

    // MARK: - File loading

    func load(url: URL) {
        print("[FileLoader] Starting file load request for: \(url.lastPathComponent)")
        if isMicLive { stopMic() }
        player.stop()
        playbackID &+= 1
        isPlaying = false
        isLoading = true
        errorMessage = nil
        let scoped = url.startAccessingSecurityScopedResource()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Guard against empty files or locked descriptors before opening
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let fileSize = attributes[.size] as? UInt64, fileSize > 0 else {
                DispatchQueue.main.async {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    self?.isLoading = false
                    self?.errorMessage = "Recorded file was empty."
                    print("[FileLoader] FAILURE: File at \(url.path) is 0 bytes or unreadable.")
                }
                return
            }

            do {
                let f = try AVAudioFile(forReading: url)
                DispatchQueue.main.async {
                    print("[FileLoader] SUCCESS: File loaded successfully into memory.")
                    self?.finishLoading(file: f, url: url, scoped: scoped)
                }
            } catch {
                DispatchQueue.main.async {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    self?.isLoading = false
                    self?.errorMessage = "Couldn't open that file."
                    print("[FileLoader] FAILURE: Could not open file at path \(url.path). Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func finishLoading(file f: AVAudioFile, url: URL, scoped: Bool) {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil
        file = f
        fileName = url.lastPathComponent
        restartEngine()
        isLoading = false
        print("[FileLoader] File '\(fileName ?? "Unknown")' attached to processing pipeline.")

        if autoPlayOnLoad {
            print("[FileLoader] Auto-play setting is active. Triggering playback automatically.")
            play()
        }
    }

    // MARK: - Playback

    func play() {
        guard file != nil, !isLoading else {
            print("[Playback] WARNING: Play call ignored. No active file or file is currently loading.")
            return
        }
        if !engine.isRunning {
            print("[Playback] Engine is stopped. Attempting engine start before playing...")
            guard startEngine() else {
                print("[Playback] FAILURE: Could not start engine. Playback aborted.")
                return
            }
            armFile()
        }
        player.play()
        isPlaying = true
        print("[Playback] SUCCESS: Playback started for '\(fileName ?? "Unknown")'.")
    }

    func stop() {
        player.stop()
        isPlaying = false
        armFile()
        print("[Playback] SUCCESS: Playback stopped and player armed for reset.")
    }

    private func armFile() {
        guard let file = file, engine.isRunning else { return }
        file.framePosition = 0
        playbackID &+= 1
        let id = playbackID
        
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.playbackID == id else { return }
                self.player.stop()
                self.isPlaying = false
                print("[Playback] Reached end of stream. Loop reset complete.")
                self.armFile()
            }
        }
        
        let safeBuffer = max(256, userBufferSize)
        player.prepare(withFrameCount: safeBuffer)
    }

    // MARK: - Output engine plumbing

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            if isMicLive {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                print("[AudioSession] Configured category: playAndRecord.")
            } else {
                try session.setCategory(.playback)
                print("[AudioSession] Configured category: playback.")
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[AudioSession] SUCCESS: Audio session activated.")
        } catch {
            print("[AudioSession] FAILURE: Could not configure audio session: \(error.localizedDescription)")
        }
        #endif
    }

    private func applyPreferredDevices() {
        #if os(macOS)
        let inputID = preferredInputDeviceID == 0
            ? defaultAudioDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
            : preferredInputDeviceID
        let outputID = preferredOutputDeviceID == 0
            ? defaultAudioDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
            : preferredOutputDeviceID
        setAudioUnitDevice(micEngine.inputNode.audioUnit, deviceID: inputID)
        setAudioUnitDevice(engine.outputNode.audioUnit, deviceID: outputID)
        let inputLabel = inputID == 0 ? "System Default" : String(inputID)
        let outputLabel = outputID == 0 ? "System Default" : String(outputID)
        print("[AudioDevices] Input: \(inputLabel), Output: \(outputLabel)")
        #endif
    }

    #if os(macOS)
    private func defaultAudioDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return deviceID
    }

    private func setAudioUnitDevice(_ audioUnit: AudioUnit?, deviceID: AudioDeviceID) {
        guard let audioUnit else { return }
        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            print("[AudioDevices] WARNING: Could not select device \(deviceID). OSStatus: \(status)")
        }
    }
    #endif

    private func refreshGraphFormat() {
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let selectedRate = userSampleRate > 0 ? userSampleRate : hardwareRate
        let validRate = selectedRate > 0 ? selectedRate : 44100.0
        
        // Always fall back to standard 44.1kHz stereo if format allocation fails
        graphFormat = AVAudioFormat(standardFormatWithSampleRate: validRate, channels: 2)
            ?? AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 2)!
        
        print("[GraphFormat] Updated processing format: \(graphFormat.sampleRate) Hz, \(graphFormat.channelCount) Channels.")
    }

    @discardableResult
    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        configureSession()
        do {
            engine.prepare()
            try engine.start()
            print("[AudioEngine] SUCCESS: Main AVAudioEngine started.")
            return true
        } catch {
            errorMessage = "Audio engine failed to start."
            print("[AudioEngine] FAILURE: Main AVAudioEngine failed to start: \(error.localizedDescription)")
            return false
        }
    }

    private func restartEngine() {
        print("[AudioEngine] Restarting main engine graph...")
        if isRecording { finishRecording(load: false) }
        playbackID &+= 1
        isPlaying = false

        micLock.lock()
        micGeneration &+= 1
        pendingMicBuffers = 0
        micPlayerReady = false
        micLock.unlock()

        micPlayer.stop()
        engine.stop()
        applyPreferredDevices()
        configureSession()
        refreshGraphFormat()
        rebuildChain()
        connectPlayer()
        connectMic()
        if file != nil || isMicLive {
            if startEngine() {
                armFile()
                if micConnected {
                    micPlayer.play()
                    micLock.lock()
                    micPlayerReady = true
                    micLock.unlock()
                }
            }
        }
        print("[AudioEngine] SUCCESS: Engine graph restart cycle completed.")
    }

    private func connectPlayer() {
        engine.disconnectNodeOutput(player)
        guard file != nil else { return }
        
        // Connect using graphFormat so the mixer and effect chain share the exact same format
        engine.connect(player, to: sourceMixer, fromBus: 0, toBus: 0, format: graphFormat)
        print("[AudioEngine] Connected file player node to source mixer using graphFormat.")
    }

    private func connectMic() {
        engine.disconnectNodeOutput(micPlayer)
        micConnected = false
        guard isMicLive, let format = micFormat else { return }
        engine.connect(micPlayer, to: sourceMixer, fromBus: 0, toBus: 1, format: format)
        micConnected = true
        print("[AudioEngine] Connected microphone player node to source mixer.")
    }

    private func rebuildChain() {
        let gf = graphFormat
        let validRate = gf.sampleRate > 0 ? gf.sampleRate : 44100.0
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: validRate, channels: 1) else { return }
        
        engine.disconnectNodeOutput(sourceMixer)
        effects.forEach { engine.disconnectNodeOutput($0.unit) }
        engine.disconnectNodeOutput(spatial.mixer)
        engine.disconnectNodeOutput(spatial.environment)

        var previous: AVAudioNode = sourceMixer
        for fx in effects {
            engine.connect(previous, to: fx.unit, format: gf)
            previous = fx.unit
        }
        if spatial.isEnabled {
            engine.connect(previous, to: spatial.mixer, format: gf)
            engine.connect(spatial.mixer, to: spatial.environment, format: mono)
            engine.connect(spatial.environment, to: engine.mainMixerNode, format: gf)
            print("[EffectsChain] Built active chain with Spatial Stage enabled.")
        } else {
            engine.connect(previous, to: engine.mainMixerNode, format: gf)
            print("[EffectsChain] Built active chain without Spatial Stage.")
        }
        spatial.apply()
        print("[EffectsChain] SUCCESS: All effect nodes linked successfully.")
    }

    // MARK: - Microphone

    func setSource(_ newSource: Source) {
        print("[SourceSelector] Source changed to: \(newSource.rawValue)")
        switch newSource {
        case .mic: startMic()
        case .file: stopMic()
        }
    }

    func startMic() {
        guard !isMicLive else { return }
        print("[Microphone] Requesting hardware permission...")
        #if os(iOS)
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    print("[Microphone] SUCCESS: Permission granted on iOS.")
                    self.beginMic()
                } else {
                    self.errorMessage = "Microphone access is off. Turn it on in Settings."
                    print("[Microphone] FAILURE: Permission denied on iOS.")
                }
            }
        }
        #else
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    print("[Microphone] SUCCESS: Permission granted on macOS.")
                    self.beginMic()
                } else {
                    self.errorMessage = "Microphone access is off. Turn it on in Settings."
                    print("[Microphone] FAILURE: Permission denied on macOS.")
                }
            }
        }
        #endif
    }

    private func beginMic() {
        errorMessage = nil
        isMicLive = true
        configureSession()
        applyPreferredDevices()

        let input = micEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone input is available."
            isMicLive = false
            print("[Microphone] FAILURE: Invalid audio format or input hardware offline.")
            return
        }
        micFormat = format
        installMicTap()
        do {
            micEngine.prepare()
            try micEngine.start()
            print("[Microphone] SUCCESS: Mic tap installed and mic engine started.")
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "Couldn't start the microphone."
            isMicLive = false
            print("[Microphone] FAILURE: Could not start mic engine: \(error.localizedDescription)")
            return
        }
        restartEngine()
    }

    private func installMicTap() {
        guard let format = micFormat else { return }
        let input = micEngine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: userBufferSize, format: format) { [weak self] buffer, _ in
            self?.handleMic(buffer)
        }
    }

    func stopMic() {
        if isRecording { finishRecording(load: false) }
        guard isMicLive else { return }
        isMicLive = false
        micEngine.inputNode.removeTap(onBus: 0)
        micEngine.stop()
        print("[Microphone] SUCCESS: Microphone stopped and tap uninstalled.")
        restartEngine()
    }

    private func handleMic(_ buffer: AVAudioPCMBuffer) {
        micLock.lock()
        let out = recordingFile
        let canQueue = micPlayerReady && pendingMicBuffers < 6
        let generation = micGeneration
        if canQueue { pendingMicBuffers += 1 }
        micLock.unlock()

        if let out = out { try? out.write(from: buffer) }
        guard canQueue else { return }

        guard let copy = AudioEngineManager.copy(buffer) else {
            micLock.lock()
            if micGeneration == generation { pendingMicBuffers = max(0, pendingMicBuffers - 1) }
            micLock.unlock()
            return
        }
        micPlayer.scheduleBuffer(copy, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard let self = self else { return }
            self.micLock.lock()
            if self.micGeneration == generation { self.pendingMicBuffers = max(0, self.pendingMicBuffers - 1) }
            self.micLock.unlock()
        }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let src = buffer.floatChannelData,
              let dst = out.floatChannelData else { return nil }
        out.frameLength = buffer.frameLength
        for channel in 0..<Int(buffer.format.channelCount) {
            dst[channel].assign(from: src[channel], count: Int(buffer.frameLength))
        }
        return out
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording { finishRecording(load: true) } else { startRecording() }
    }

    private func startRecording() {
        guard isMicLive, let format = micFormat else {
            errorMessage = "Start the mic first."
            print("[Recorder] WARNING: Recording attempt aborted. Microphone is not active.")
            return
        }
        
        // 1. Switch to WAV to match Sound Lab's proven saving method
        let fileName = "Mic-\(Int(Date().timeIntervalSince1970)).wav"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        // 2. Force standard interleaved formatting so WAV doesn't crash on initialization
        guard let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: format.sampleRate,
                                             channels: format.channelCount,
                                             interleaved: true) else { return }
        
        do {
            let out = try AVAudioFile(forWriting: url, settings: fileFormat.settings)
            micLock.lock()
            recordingFile = out
            micLock.unlock()
            recordingURL = url
            isRecording = true
            
            print("[Recorder] SUCCESS: Recording started. Target file: \(url.path)")
        } catch {
            errorMessage = "Couldn't start recording."
            print("[Recorder] FAILURE: Could not write output file: \(error.localizedDescription)")
        }
    }

    private func finishRecording(load shouldLoad: Bool) {
        // Immediately toggle state to prevent infinite loops with stopMic()
        isRecording = false
        if shouldLoad { stopMic() }
        
        micLock.lock()
        var fileToClose: AVAudioFile? = recordingFile
        recordingFile = nil
        micLock.unlock()
        
        let safeURL = recordingURL
        recordingURL = nil
        
        // 3. EXPLICITLY KILL THE WRITER NOW. Do not let ARC wait for the function scope to end.
        fileToClose = nil
        
        print("[Recorder] SUCCESS: Recording finalized.")
        
        guard shouldLoad, let url = safeURL else { return }
        
        // 4. Give the OS disk a half-second to flush the WAV header before ripping it open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.load(url: url)
        }
    }

    // MARK: - Parameter and Effect Mutation Handlers

    func setEffectEnabled(_ effect: EffectModule, enabled: Bool) {
        guard let index = effects.firstIndex(where: { $0.id == effect.id }) else {
            print("[EffectsManager] FAILURE: Could not find effect with key '\(effect.key)'")
            return
        }
        effects[index].isEnabled = enabled
        print("[EffectsManager] SUCCESS: Set '\(effects[index].key)' enabled state to: \(enabled)")
    }

    func updateParameter(effect: EffectModule, parameterID: String, value: Float) {
        guard let fxIndex = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        if let paramIndex = effects[fxIndex].parameters.firstIndex(where: { $0.id == parameterID }) {
            effects[fxIndex].parameters[paramIndex].value = value
            print("[EffectsManager] SUCCESS: Updated '\(effects[fxIndex].key)' parameter '\(parameterID)' -> \(value)")
        }
    }

    func move(_ effect: EffectModule, by offset: Int) {
        guard let i = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        let j = i + offset
        guard effects.indices.contains(j) else {
            print("[EffectsManager] WARNING: Cannot move effect '\(effect.key)' out of index bounds.")
            return
        }
        if isPlaying { stop() }
        effects.swapAt(i, j)
        rebuildChain()
        print("[EffectsManager] SUCCESS: Moved '\(effect.key)' from index \(i) to \(j).")
    }

    func randomize() {
        for fx in effects {
            for i in fx.parameters.indices {
                fx.parameters[i].value = Float.random(in: fx.parameters[i].range)
            }
            fx.isEnabled = Bool.random()
        }
        print("[EffectsManager] SUCCESS: All parameters randomized across active modules.")
    }

    func resetAll() {
        effects.forEach { $0.reset() }
        print("[EffectsManager] SUCCESS: All effect parameters reset to defaults.")
    }

    // MARK: - Presets

    func snapshot(name: String) -> Preset {
        let preset = Preset(name: name, effects: effects.map { fx in
            EffectState(
                key: fx.key,
                enabled: fx.isEnabled,
                values: Dictionary(uniqueKeysWithValues: fx.parameters.map { ($0.id, $0.value) })
            )
        })
        print("[Presets] SUCCESS: Captured preset snapshot named '\(name)' with \(preset.effects.count) effects.")
        return preset
    }

    func apply(_ preset: Preset) {
        for state in preset.effects {
            guard let fx = effects.first(where: { $0.key == state.key }) else { continue }
            for i in fx.parameters.indices {
                if let v = state.values[fx.parameters[i].id] { fx.parameters[i].value = v }
            }
            fx.isEnabled = state.enabled
        }
        print("[Presets] SUCCESS: Applied preset '\(preset.name)' to current engine state.")
    }
}
