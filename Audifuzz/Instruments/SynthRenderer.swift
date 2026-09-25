import AVFoundation

/// Plain, fixed-size voice settings the audio thread can read safely.
struct VoiceParams {
    var enabled = false
    var frequency: Float = 440
    var wave: Int32 = 0
    var volume: Float = 0.5
    var pan: Float = 0
    var sweep: Float = 0
    var sweepRate: Float = 1
}

struct MIDINoteParams {
    var active = false
    var frequency: Float = 440
    var velocity: Float = 1
    var pitchBend: Float = 1
    var modulation: Float = 0
    var pressure: Float = 1
    var selectedVoice = -1
}

/// Running state for one source node (phases, smoothed pitch/volume).
private final class VoiceState {
    let phase: UnsafeMutablePointer<Double>
    let lfo: UnsafeMutablePointer<Double>
    let freq: UnsafeMutablePointer<Float>
    let vol: UnsafeMutablePointer<Float>

    init() {
        let n = SynthRenderer.maxVoices + SynthRenderer.maxMIDINotes
        phase = .allocate(capacity: n); phase.initialize(repeating: 0, count: n)
        lfo = .allocate(capacity: n); lfo.initialize(repeating: 0, count: n)
        freq = .allocate(capacity: n); freq.initialize(repeating: 0, count: n)
        vol = .allocate(capacity: n); vol.initialize(repeating: 0, count: n)
    }

    deinit {
        phase.deallocate(); lfo.deallocate(); freq.deallocate(); vol.deallocate()
    }
}

/// Generates the stacked waves. The main thread writes settings into `params`;
/// the audio thread only reads them, so there are no locks or allocations while rendering.
final class SynthRenderer {
    static let maxVoices = 8
    static let maxMIDINotes = 16
    private let params: UnsafeMutablePointer<VoiceParams>
    private let midiParams: UnsafeMutablePointer<MIDINoteParams>
    private let baseVoicesMuted: UnsafeMutablePointer<Bool>

    init() {
        params = .allocate(capacity: SynthRenderer.maxVoices)
        params.initialize(repeating: VoiceParams(), count: SynthRenderer.maxVoices)
        midiParams = .allocate(capacity: SynthRenderer.maxMIDINotes)
        midiParams.initialize(repeating: MIDINoteParams(), count: SynthRenderer.maxMIDINotes)
        baseVoicesMuted = .allocate(capacity: 1)
        baseVoicesMuted.initialize(to: false)
    }

    deinit {
        params.deallocate()
        midiParams.deallocate()
        baseVoicesMuted.deallocate()
    }

    func setBaseVoicesMuted(_ muted: Bool) { baseVoicesMuted.pointee = muted }

    func startMIDINote(slot: Int, note: UInt8, velocity: Float, selectedVoice: Int) {
        guard (0..<SynthRenderer.maxMIDINotes).contains(slot) else { return }
        midiParams[slot] = MIDINoteParams(
            active: true,
            frequency: 440 * powf(2, (Float(note) - 69) / 12),
            velocity: max(0, min(1, velocity)),
            pitchBend: midiParams[slot].pitchBend,
            modulation: midiParams[slot].modulation,
            pressure: 1,
            selectedVoice: selectedVoice
        )
    }

    func stopMIDINote(slot: Int) {
        guard (0..<SynthRenderer.maxMIDINotes).contains(slot) else { return }
        midiParams[slot].active = false
    }

    func setMIDIPitchBend(_ multiplier: Float) {
        for slot in 0..<SynthRenderer.maxMIDINotes {
            midiParams[slot].pitchBend = multiplier
        }
    }

    func setMIDIModulation(_ amount: Float) {
        let value = max(0, min(1, amount))
        for slot in 0..<SynthRenderer.maxMIDINotes { midiParams[slot].modulation = value }
    }

    func setMIDIPressure(slot: Int, amount: Float) {
        guard (0..<SynthRenderer.maxMIDINotes).contains(slot) else { return }
        midiParams[slot].pressure = max(0, min(1, amount))
    }

    func update(_ voices: [Voice]) {
        for i in 0..<SynthRenderer.maxVoices {
            if i < voices.count {
                let v = voices[i]
                params[i] = VoiceParams(enabled: v.enabled, frequency: v.frequency,
                                        wave: Int32(v.wave.rawValue), volume: v.volume,
                                        pan: v.pan, sweep: v.sweep, sweepRate: v.sweepRate)
            } else {
                params[i].enabled = false
            }
        }
    }

    /// Each call gets its own fresh state, so the live preview and the
    /// offline "save" render don't disturb each other.
    func makeSourceNode(sampleRate: Double) -> AVAudioSourceNode {
        let state = VoiceState()
        let params = self.params
        let midiParams = self.midiParams
        let baseVoicesMuted = self.baseVoicesMuted
        let count = SynthRenderer.maxVoices
        let master: Float = 0.25
        let twoPi = Float.pi * 2
        let smoothing: Float = 0.002
        return AVAudioSourceNode { [self] _, _, frameCount, audioBufferList -> OSStatus in
            _ = self   // keeps the renderer (and its params) alive while the node exists
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let left = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            // Snapshot the fixed-size settings once per buffer. MIDI note counts
            // must be read here (not when the node is created) as keys change.
            let activeMIDINotes = max(1, (0..<SynthRenderer.maxMIDINotes).reduce(0) { total, slot in
                total + (midiParams[slot].active ? 1 : 0)
            })
            let enabledBaseVoices = max(1, (0..<count).reduce(0) { $0 + (params[$1].enabled ? 1 : 0) })

            for frame in 0..<Int(frameCount) {
                var l: Float = 0
                var r: Float = 0
                for v in 0..<count {
                    let p = params[v]
                    let targetVol: Float = p.enabled && !baseVoicesMuted.pointee ? p.volume : 0
                    if targetVol == 0 && state.vol[v] < 0.00001 { state.vol[v] = 0; continue }
                    if state.freq[v] == 0 { state.freq[v] = p.frequency }

                    state.vol[v] += (targetVol - state.vol[v]) * smoothing
                    state.freq[v] += (p.frequency - state.freq[v]) * smoothing

                    state.phase[v] += Double(state.freq[v]) / sampleRate
                    if state.phase[v] >= 1 { state.phase[v] -= 1 }
                    state.lfo[v] += Double(p.sweepRate) / sampleRate
                    if state.lfo[v] >= 1 { state.lfo[v] -= 1 }

                    let ph = Float(state.phase[v])
                    let s: Float
                    switch p.wave {
                    case 1: s = ph < 0.5 ? 1 : -1              // square
                    case 2: s = 4 * abs(ph - 0.5) - 1          // triangle
                    case 3: s = 2 * ph - 1                     // saw
                    default: s = sinf(twoPi * ph)              // round (sine)
                    }

                    let position = min(max(p.pan + p.sweep * sinf(twoPi * Float(state.lfo[v])), -1), 1)
                    let angle = (position + 1) * Float.pi / 4  // equal-power pan
                    let gain = s * state.vol[v] / Float(enabledBaseVoices)
                    l += gain * cosf(angle)
                    r += gain * sinf(angle)
                }
                for noteSlot in 0..<SynthRenderer.maxMIDINotes {
                    let note = midiParams[noteSlot]
                    let stateIndex = count + noteSlot
                    let targetVol: Float = note.active ? note.velocity : 0
                    if targetVol == 0 && state.vol[stateIndex] < 0.00001 {
                        state.vol[stateIndex] = 0
                        continue
                    }
                    state.vol[stateIndex] += (targetVol - state.vol[stateIndex]) * smoothing
                    state.lfo[stateIndex] += 5 / sampleRate
                    if state.lfo[stateIndex] >= 1 { state.lfo[stateIndex] -= 1 }
                    let vibrato = 1 + sinf(twoPi * Float(state.lfo[stateIndex])) * note.modulation * 0.004
                    let targetFrequency = note.frequency * note.pitchBend * vibrato
                    state.freq[stateIndex] += (targetFrequency - state.freq[stateIndex]) * smoothing
                    if state.freq[stateIndex] == 0 { state.freq[stateIndex] = targetFrequency }
                    state.phase[stateIndex] += Double(state.freq[stateIndex]) / sampleRate
                    if state.phase[stateIndex] >= 1 { state.phase[stateIndex] -= 1 }
                    let phase = Float(state.phase[stateIndex])
                    let enabledMIDIVoices = max(1, (0..<count).reduce(0) { total, instrument in
                        let voice = params[instrument]
                        return total + (voice.enabled && (note.selectedVoice < 0 || note.selectedVoice == instrument) ? 1 : 0)
                    })
                    for instrument in 0..<count {
                        let voice = params[instrument]
                        guard voice.enabled, note.selectedVoice < 0 || note.selectedVoice == instrument else { continue }
                        let wave: Float
                        switch voice.wave {
                        case 1: wave = phase < 0.5 ? 1 : -1
                        case 2: wave = 4 * abs(phase - 0.5) - 1
                        case 3: wave = 2 * phase - 1
                        default: wave = sinf(twoPi * phase)
                        }
                        let position = min(max(voice.pan, -1), 1)
                        let angle = (position + 1) * Float.pi / 4
                        let gain = wave * state.vol[stateIndex] * note.pressure * voice.volume / Float(enabledMIDIVoices * activeMIDINotes)
                        l += gain * cosf(angle)
                        r += gain * sinf(angle)
                    }
                }
                left[frame] = min(max(l * master, -1), 1)
                right[frame] = min(max(r * master, -1), 1)
            }
            return noErr
        }
    }
}
