import AVFoundation
import SwiftUI

private struct LabError: Error {}

/// The Sound Lab: stacked waves -> 5-band equalizer -> speakers, plus saving to a file.
final class SoundLabEngine: ObservableObject {
    static let eqFrequencies: [Float] = [60, 250, 1000, 4000, 12000]

    @Published var voices: [Voice] = [Voice()] { didSet { renderer.update(voices) } }
    @Published var eqGains: [Float] = [0, 0, 0, 0, 0] {
        didSet { SoundLabEngine.configureEQ(eq, gains: eqGains) }
    }
    @Published var duration: Float = 4                      // seconds to save
    @Published private(set) var isPlaying = false
    @Published private(set) var isSaving = false
    @Published var statusMessage: String?
    @Published private(set) var samples: [URL] = []

    private let renderer = SynthRenderer()
    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: SoundLabEngine.eqFrequencies.count)
    private var sourceNode: AVAudioSourceNode?

    init() {
        renderer.update(voices)
        SoundLabEngine.configureEQ(eq, gains: eqGains)
        refreshSamples()
    }

    // MARK: - Instruments

    func addVoice() {
        guard voices.count < SynthRenderer.maxVoices else { return }
        let base = voices.last?.frequency ?? 220
        voices.append(Voice(frequency: min(base * 1.5, 5000)))
    }

    func removeVoice(_ id: UUID) {
        guard voices.count > 1 else { return }
        voices.removeAll { $0.id == id }
    }

    /// A binding that looks the voice up by id, so it stays safe when voices are removed.
    func binding(for id: UUID) -> Binding<Voice> {
        Binding(
            get: { self.voices.first { $0.id == id } ?? Voice() },
            set: { newValue in
                if let i = self.voices.firstIndex(where: { $0.id == id }) { self.voices[i] = newValue }
            })
    }

    // MARK: - Live preview

    func togglePlay() {
        if isPlaying { stopPreview() } else { startPreview() }
    }

    private func buildGraphIfNeeded() {
        guard sourceNode == nil else { return }
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = rate > 0 ? rate : 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = renderer.makeSourceNode(sampleRate: sampleRate)
        engine.attach(node)
        engine.attach(eq)
        engine.connect(node, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    private func startPreview() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        buildGraphIfNeeded()
        do {
            try engine.start()
            isPlaying = true
        } catch {
            statusMessage = "Couldn't start the preview."
        }
    }

    func stopPreview() {
        guard isPlaying else { return }
        engine.stop()
        isPlaying = false
    }

    // MARK: - Equalizer

    static func configureEQ(_ unit: AVAudioUnitEQ, gains: [Float]) {
        for (i, band) in unit.bands.enumerated() where i < eqFrequencies.count {
            if i == 0 {
                band.filterType = .lowShelf
            } else if i == eqFrequencies.count - 1 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
            }
            band.frequency = eqFrequencies[i]
            band.bandwidth = 1
            band.gain = gains[i]
            band.bypass = false
        }
    }

    // MARK: - Saving

    func saveSample() {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = "Saving…"
        let seconds = Double(duration)
        let gains = eqGains
        let renderer = self.renderer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<URL, Error>
            do {
                result = .success(try SoundLabEngine.renderSample(renderer: renderer, gains: gains, seconds: seconds))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSaving = false
                switch result {
                case .success(let url):
                    self.statusMessage = "Saved \(url.lastPathComponent)"
                    self.refreshSamples()
                case .failure:
                    self.statusMessage = "Couldn't save the sound."
                }
            }
        }
    }

    /// Renders exactly what you hear (waves + equalizer) to a WAV file, faster than real time.
    private static func renderSample(renderer: SynthRenderer, gains: [Float], seconds: Double) throws -> URL {
        let sampleRate = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let offline = AVAudioEngine()
        let source = renderer.makeSourceNode(sampleRate: sampleRate)
        let offlineEQ = AVAudioUnitEQ(numberOfBands: eqFrequencies.count)
        configureEQ(offlineEQ, gains: gains)
        offline.attach(source)
        offline.attach(offlineEQ)
        offline.connect(source, to: offlineEQ, format: format)
        offline.connect(offlineEQ, to: offline.mainMixerNode, format: format)
        try offline.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try offline.start()

        let url = SampleStorage.newURL(prefix: "Sound", ext: "wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: offline.manualRenderingFormat,
                                            frameCapacity: offline.manualRenderingMaximumFrameCount) else {
            throw LabError()
        }
        var remaining = AVAudioFrameCount(seconds * sampleRate)
        while remaining > 0 {
            let n = min(remaining, buffer.frameCapacity)
            let status = try offline.renderOffline(n, to: buffer)
            guard status == .success else { throw LabError() }
            try file.write(from: buffer)
            remaining -= n
        }
        offline.stop()
        return url
    }

    // MARK: - Saved samples

    func refreshSamples() { samples = SampleStorage.list() }

    func deleteSample(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshSamples()
    }
}
