import AVFoundation

/// Owns the audio engine and the ordered effect chain:
/// player -> effect 1 -> effect 2 -> ... -> main mixer -> output
final class AudioEngineManager: ObservableObject {
    @Published private(set) var effects: [EffectModule]
    @Published private(set) var isPlaying = false
    @Published private(set) var fileName: String?
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var scopedURL: URL?
    private var playbackID = 0

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
        effects.forEach { engine.attach($0.unit) }
        rebuildChain(format: nil)
    }

    // MARK: - File + playback

    func load(url: URL) {
        stop()
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        do {
            let f = try AVAudioFile(forReading: url)
            file = f
            fileName = url.lastPathComponent
            errorMessage = nil
            rebuildChain(format: f.processingFormat)
        } catch {
            errorMessage = "Couldn't open that file."
        }
    }

    func play() {
        guard let file = file else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            errorMessage = "Audio engine failed to start."
            return
        }
        player.stop()
        file.framePosition = 0
        playbackID &+= 1
        let id = playbackID
        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.playbackID == id else { return }
                self.isPlaying = false
            }
        }
        player.play()
        isPlaying = true
    }

    func stop() {
        playbackID &+= 1
        player.stop()
        isPlaying = false
    }

    // MARK: - Chain editing

    /// Move an effect up (-1) or down (+1) in the chain.
    func move(_ effect: EffectModule, by offset: Int) {
        guard let i = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        let j = i + offset
        guard effects.indices.contains(j) else { return }
        stop()
        effects.swapAt(i, j)
        rebuildChain(format: file?.processingFormat)
    }

    private func rebuildChain(format: AVAudioFormat?) {
        engine.disconnectNodeOutput(player)
        effects.forEach { engine.disconnectNodeOutput($0.unit) }
        var previous: AVAudioNode = player
        for fx in effects {
            engine.connect(previous, to: fx.unit, format: format)
            previous = fx.unit
        }
        engine.connect(previous, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Fun stuff

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
