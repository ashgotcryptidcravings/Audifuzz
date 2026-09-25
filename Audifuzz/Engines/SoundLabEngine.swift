import AVFoundation
import SwiftUI

private struct LabError: Error {}

/// The Sound Lab: stacked waves -> 5-band equalizer -> speakers, plus saving to a file.
final class SoundLabEngine: ObservableObject {
    static let eqFrequencies: [Float] = [60, 250, 1000, 4000, 12000]

    @Published var voices: [Voice] = [Voice()] {
        didSet {
            renderer.update(voices)
        }
    }
    
    @Published var eqGains: [Float] = [0, 0, 0, 0, 0] {
        didSet {
            SoundLabEngine.configureEQ(eq, gains: eqGains)
        }
    }
    
    @Published var duration: Float = 4 {
        didSet {
            print("[SoundLabEngine] Target save duration changed to: \(duration) seconds")
        }
    }
    
    @Published private(set) var isPlaying = false
    @Published private(set) var isMIDIActive = false
    @Published private(set) var isSaving = false
    @Published private(set) var waveform = Array(repeating: Float.zero, count: 128)
    @Published private(set) var waveformRight = Array(repeating: Float.zero, count: 128)
    @Published var statusMessage: String? {
        didSet {
            if let msg = statusMessage {
                print("[SoundLabEngine] Status message: '\(msg)'")
            }
        }
    }
    @Published private(set) var samples: [URL] = []

    private let renderer = SynthRenderer()
    private var midiSlots: [Int: Int] = [:]
    private var nextMIDISlot = 0
    private var isManualPreview = false
    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: SoundLabEngine.eqFrequencies.count)
    private var sourceNode: AVAudioSourceNode?

    init() {
        print("[SoundLabEngine] Initializing Sound Lab engine...")
        renderer.update(voices)
        SoundLabEngine.configureEQ(eq, gains: eqGains)
        BuiltInSoundLibrary.install()
        refreshSamples()
        print("[SoundLabEngine] Initialization complete.")
    }

    // MARK: - Instruments

    func addVoice() {
        guard voices.count < SynthRenderer.maxVoices else {
            print("[SoundLabEngine] WARNING: Max voices reached (\(SynthRenderer.maxVoices)). Cannot add more.")
            return
        }
        let base = voices.last?.frequency ?? 220
        let newFreq = min(base * 1.5, 5000)
        voices.append(Voice(frequency: newFreq))
        print("[SoundLabEngine] SUCCESS: Added new voice at frequency: \(newFreq) Hz")
    }

    func removeVoice(_ id: UUID) {
        guard voices.count > 1 else {
            print("[SoundLabEngine] WARNING: Cannot remove last remaining voice.")
            return
        }
        voices.removeAll { $0.id == id }
        print("[SoundLabEngine] SUCCESS: Removed voice with ID: \(id)")
    }

    /// A binding that looks the voice up by id, so it stays safe when voices are removed.
    func binding(for id: UUID) -> Binding<Voice> {
        Binding(
            get: { self.voices.first { $0.id == id } ?? Voice() },
            set: { newValue in
                if let i = self.voices.firstIndex(where: { $0.id == id }) {
                    self.voices[i] = newValue
                }
            })
    }

    // MARK: - Live preview

    func togglePlay() {
        print("[SoundLabEngine] Toggle preview playback requested...")
        if isPlaying {
            isManualPreview = false
            renderer.setBaseVoicesMuted(true)
            stopPreview()
        } else {
            isManualPreview = true
            renderer.setBaseVoicesMuted(false)
            startPreview()
        }
    }

    func receiveMIDINoteOn(channel: Int, note: UInt8, velocity: UInt8, mode: Int,
                           selectedInstrument: Int, velocityEnabled: Bool) {
        isMIDIActive = true
        if !isManualPreview { renderer.setBaseVoicesMuted(true) }
        if !isPlaying { startPreview() }
        let noteID = channel * 128 + Int(note)
        let slot: Int
        if let existing = midiSlots[noteID] {
            slot = existing
        } else {
            let occupied = Set(midiSlots.values)
            if let available = (0..<SynthRenderer.maxMIDINotes).first(where: { !occupied.contains($0) }) {
                slot = available
            } else {
                slot = nextMIDISlot
                midiSlots = midiSlots.filter { $0.value != slot }
                renderer.stopMIDINote(slot: slot)
            }
            nextMIDISlot = (slot + 1) % SynthRenderer.maxMIDINotes
        }
        midiSlots[noteID] = slot
        let amplitude = velocityEnabled ? Float(velocity) / 127 : 1
        let targetVoice: Int
        if mode == 1 {
            targetVoice = -1
        } else if voices.indices.contains(selectedInstrument), voices[selectedInstrument].enabled {
            targetVoice = selectedInstrument
        } else {
            targetVoice = voices.firstIndex(where: \.enabled) ?? selectedInstrument
        }
        renderer.startMIDINote(slot: slot, note: note, velocity: amplitude,
                               selectedVoice: targetVoice)
    }

    func receiveMIDINoteOff(channel: Int, note: UInt8) {
        let noteID = channel * 128 + Int(note)
        guard let slot = midiSlots.removeValue(forKey: noteID) else { return }
        renderer.stopMIDINote(slot: slot)
        updateMIDIActiveState()
    }

    func receiveMIDIPitchBend(value: Int, rangeInSemitones: Int) {
        let normalized = Float(value - 8192) / 8192
        let semitones = normalized * Float(rangeInSemitones)
        renderer.setMIDIPitchBend(powf(2, semitones / 12))
    }

    func receiveMIDIModulation(value: UInt8) {
        renderer.setMIDIModulation(Float(value) / 127)
    }

    func receiveMIDIChannelPressure(channel: Int, value: UInt8) {
        for (noteID, slot) in midiSlots where noteID / 128 == channel {
            renderer.setMIDIPressure(slot: slot, amount: Float(value) / 127)
        }
    }

    func receiveMIDIPolyPressure(channel: Int, note: UInt8, value: UInt8) {
        let noteID = channel * 128 + Int(note)
        guard let slot = midiSlots[noteID] else { return }
        renderer.setMIDIPressure(slot: slot, amount: Float(value) / 127)
    }

    func receiveMIDIAllNotesOff() {
        for noteID in Array(midiSlots.keys) {
            if let slot = midiSlots.removeValue(forKey: noteID) { renderer.stopMIDINote(slot: slot) }
        }
        updateMIDIActiveState()
    }

    func stopManualPreview() {
        guard !isMIDIActive else { return }
        stopPreview()
    }

    private func updateMIDIActiveState() {
        isMIDIActive = !midiSlots.isEmpty
        if !isMIDIActive && !isManualPreview {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                guard let self, !self.isMIDIActive, !self.isManualPreview else { return }
                self.stopPreview()
            }
        }
    }

    private func buildGraphIfNeeded() {
        guard sourceNode == nil else { return }
        print("[SoundLabEngine] Building internal preview audio graph...")
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = rate > 0 ? rate : 44100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = renderer.makeSourceNode(sampleRate: sampleRate)
        engine.attach(node)
        engine.attach(eq)
        engine.connect(node, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, _ in
            self?.captureWaveform(from: buffer)
        }
        sourceNode = node
        print("[SoundLabEngine] Audio graph successfully linked.")
    }

    private func startPreview() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            print("[AudioSession] Configured category: playback.")
        } catch {
            print("[AudioSession] FAILURE: Could not activate session: \(error.localizedDescription)")
        }
        #endif
        
        buildGraphIfNeeded()
        do {
            try engine.start()
            isPlaying = true
            print("[SoundLabEngine] SUCCESS: Live synth preview started.")
        } catch {
            statusMessage = "Couldn't start the preview."
            print("[SoundLabEngine] FAILURE: Could not start live preview engine: \(error.localizedDescription)")
        }
    }

    func stopPreview() {
        isManualPreview = false
        for slot in midiSlots.values { renderer.stopMIDINote(slot: slot) }
        midiSlots.removeAll()
        isMIDIActive = false
        renderer.setBaseVoicesMuted(false)
        guard isPlaying else { return }
        engine.stop()
        isPlaying = false
        waveform = Array(repeating: 0, count: waveform.count)
        waveformRight = Array(repeating: 0, count: waveformRight.count)
        print("[SoundLabEngine] SUCCESS: Live synth preview stopped.")
    }

    private func captureWaveform(from buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let channelCount = Int(buffer.format.channelCount)
        let pointCount = 128
        var points = Array(repeating: Float.zero, count: pointCount)
        var rightPoints = Array(repeating: Float.zero, count: pointCount)
        for point in 0..<pointCount {
            let frame = min(frameCount - 1, point * frameCount / pointCount)
            points[point] = channels[0][frame]
            rightPoints[point] = channels[min(1, channelCount - 1)][frame]
        }

        DispatchQueue.main.async { [weak self] in
            self?.waveform = points
            self?.waveformRight = rightPoints
        }
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
        guard !isSaving else {
            print("[SoundLabEngine] WARNING: Save call ignored. Rendering already in progress.")
            return
        }
        isSaving = true
        statusMessage = "Saving…"
        let seconds = Double(duration)
        let gains = eqGains
        let renderer = self.renderer
        
        print("[SampleRenderer] Starting offline render for \(seconds) seconds...")
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
                    print("[SampleRenderer] SUCCESS: Rendered WAV file saved to: \(url.path)")
                    self.refreshSamples()
                case .failure(let error):
                    self.statusMessage = "Couldn't save the sound."
                    print("[SampleRenderer] FAILURE: Could not render audio file. Error: \(error.localizedDescription)")
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

    func refreshSamples() {
        BuiltInSoundLibrary.install()
        SampleStorage.pruneToLimit()
        samples = SampleStorage.list()
        print("[SampleStorage] Refreshed samples list. Found \(samples.count) file(s).")
    }

    func deleteSample(_ url: URL) {
        print("[SampleStorage] Attempting to delete file at: \(url.lastPathComponent)")
        do {
            try FileManager.default.removeItem(at: url)
            print("[SampleStorage] SUCCESS: Deleted \(url.lastPathComponent)")
        } catch {
            print("[SampleStorage] FAILURE: Could not delete \(url.lastPathComponent). Error: \(error.localizedDescription)")
        }
        refreshSamples()
    }
}
