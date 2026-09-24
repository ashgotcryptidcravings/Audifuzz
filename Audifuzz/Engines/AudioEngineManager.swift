import AVFoundation
import SwiftUI

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
    private var graphFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
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
        
        print("[AudioEngineManager] Initialization complete. Engine ready.")
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
        player.prepare(withFrameCount: userBufferSize)
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

    private func refreshGraphFormat() {
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let selectedRate = hardwareRate > 0 ? hardwareRate : userSampleRate
        graphFormat = AVAudioFormat(standardFormatWithSampleRate: selectedRate, channels: 2)!
        print("[GraphFormat] Updated processing format: \(selectedRate) Hz, 2 Channels.")
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
        guard let file = file else { return }
        engine.connect(player, to: sourceMixer, fromBus: 0, toBus: 0, format: file.processingFormat)
        print("[AudioEngine] Connected file player node to source mixer.")
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
        let mono = AVAudioFormat(standardFormatWithSampleRate: gf.sampleRate, channels: 1)!
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

        let input = micEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone input is available."
            isMicLive = false
            print("[Microphone] FAILURE: Invalid audio format or input hardware offline.")
            return
        }
        micFormat = format
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: userBufferSize, format: format) { [weak self] buffer, _ in
            self?.handleMic(buffer)
        }
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
        let url = SampleStorage.newURL(prefix: "Mic", ext: "caf")
        do {
            let out = try AVAudioFile(forWriting: url, settings: format.settings)
            micLock.lock()
            recordingFile = out
            micLock.unlock()
            recordingURL = url
            isRecording = true
            print("[Recorder] SUCCESS: Recording started. Target file: \(url.lastPathComponent)")
        } catch {
            errorMessage = "Couldn't start recording."
            print("[Recorder] FAILURE: Could not write output file: \(error.localizedDescription)")
        }
    }

    private func finishRecording(load shouldLoad: Bool) {
        micLock.lock()
        recordingFile = nil
        micLock.unlock()
        isRecording = false
        let url = recordingURL
        recordingURL = nil
        
        print("[Recorder] SUCCESS: Recording finalized.")
        guard shouldLoad, let url = url else { return }
        stopMic()
        load(url: url)
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
