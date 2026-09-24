import AVFoundation

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

    @Published private(set) var effects: [EffectModule]
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var fileName: String?
    @Published private(set) var isMicLive = false
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?
    let spatial = SpatialStage()

    var source: Source { isMicLive ? .mic : .file }

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
            if self.isPlaying { self.stop() }
            self.rebuildChain()
        }
        refreshGraphFormat()
        rebuildChain()

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.restartEngine() }

        // If the mic device changes (headphones plugged in, etc.), turn the mic off cleanly.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: micEngine, queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isMicLive else { return }
            self.stopMic()
            self.errorMessage = "The microphone changed. Tap Mic to start it again."
        }
    }

    // MARK: - File loading (off the main thread, with a loading flag)

    func load(url: URL) {
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
                DispatchQueue.main.async { self?.finishLoading(file: f, url: url, scoped: scoped) }
            } catch {
                DispatchQueue.main.async {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    self?.isLoading = false
                    self?.errorMessage = "Couldn't open that file."
                }
            }
        }
    }

    private func finishLoading(file f: AVAudioFile, url: URL, scoped: Bool) {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil
        file = f
        fileName = url.lastPathComponent
        restartEngine()          // connects the player, starts the engine, and queues the file
        isLoading = false
    }

    // MARK: - Playback (engine is already running, so Play is instant)

    func play() {
        guard file != nil, !isLoading else { return }
        if !engine.isRunning {
            guard startEngine() else { return }
            armFile()
        }
        player.play()
        isPlaying = true
    }

    func stop() {
        player.stop()
        isPlaying = false
        armFile()
    }

    /// Queue the file from the start so the next Play begins immediately.
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
                self.armFile()
            }
        }
        player.prepare(withFrameCount: 8192)
    }

    // MARK: - Output engine plumbing

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if isMicLive {
            try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        } else {
            try? session.setCategory(.playback)
        }
        try? session.setActive(true)
        #endif
    }

    private func refreshGraphFormat() {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        graphFormat = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44100, channels: 2)!
    }

    @discardableResult
    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        configureSession()
        do {
            engine.prepare()
            try engine.start()
            return true
        } catch {
            errorMessage = "Audio engine failed to start."
            return false
        }
    }

    /// Stop everything, rebuild all connections, and start again.
    private func restartEngine() {
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
    }

    private func connectPlayer() {
        guard let file = file else { return }
        engine.connect(player, to: sourceMixer, fromBus: 0, toBus: 0, format: file.processingFormat)
    }

    private func connectMic() {
        engine.disconnectNodeOutput(micPlayer)
        micConnected = false
        guard isMicLive, let format = micFormat else { return }
        engine.connect(micPlayer, to: sourceMixer, fromBus: 0, toBus: 1, format: format)
        micConnected = true
    }

    /// All effect connections live here.
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
        } else {
            engine.connect(previous, to: engine.mainMixerNode, format: gf)
        }
        spatial.apply()
    }

    // MARK: - Microphone (its own engine)

    func setSource(_ newSource: Source) {
        switch newSource {
        case .mic: startMic()
        case .file: stopMic()
        }
    }

    func startMic() {
        guard !isMicLive else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else {
                    self.errorMessage = "Microphone access is off. Turn it on in Settings."
                    return
                }
                self.beginMic()
            }
        }
    }

    private func beginMic() {
        errorMessage = nil
        isMicLive = true          // set first: iOS needs the record-capable audio session
        configureSession()

        let input = micEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone input is available."
            isMicLive = false
            return
        }
        micFormat = format
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleMic(buffer)
        }
        do {
            micEngine.prepare()
            try micEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "Couldn't start the microphone."
            isMicLive = false
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
        restartEngine()
    }

    /// Runs on the mic's own thread: saves to the recording (if any) and queues a copy for playback.
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

    // MARK: - Recording a mic sample

    func toggleRecording() {
        if isRecording { finishRecording(load: true) } else { startRecording() }
    }

    private func startRecording() {
        guard isMicLive, let format = micFormat else {
            errorMessage = "Start the mic first."
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
        } catch {
            errorMessage = "Couldn't start recording."
        }
    }

    private func finishRecording(load shouldLoad: Bool) {
        micLock.lock()
        recordingFile = nil
        micLock.unlock()
        isRecording = false
        let url = recordingURL
        recordingURL = nil
        guard shouldLoad, let url = url else { return }
        stopMic()
        load(url: url)
    }

    // MARK: - Chain editing and fun stuff

    /// Move an effect up (-1) or down (+1) in the chain.
    func move(_ effect: EffectModule, by offset: Int) {
        guard let i = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        let j = i + offset
        guard effects.indices.contains(j) else { return }
        if isPlaying { stop() }   // safest to reconnect while silent
        effects.swapAt(i, j)
        rebuildChain()
    }

    func randomize() {
        for fx in effects {
            for i in fx.parameters.indices {
                fx.parameters[i].value = Float.random(in: fx.parameters[i].range)
            }
            fx.isEnabled = Bool.random()
        }
    }

    func resetAll() {
        effects.forEach { $0.reset() }
    }

    // MARK: - Presets

    func snapshot(name: String) -> Preset {
        Preset(name: name, effects: effects.map { fx in
            EffectState(
                key: fx.key,
                enabled: fx.isEnabled,
                values: Dictionary(uniqueKeysWithValues: fx.parameters.map { ($0.id, $0.value) })
            )
        })
    }

    func apply(_ preset: Preset) {
        for state in preset.effects {
            guard let fx = effects.first(where: { $0.key == state.key }) else { continue }
            for i in fx.parameters.indices {
                if let v = state.values[fx.parameters[i].id] { fx.parameters[i].value = v }
            }
            fx.isEnabled = state.enabled
        }
    }
}
