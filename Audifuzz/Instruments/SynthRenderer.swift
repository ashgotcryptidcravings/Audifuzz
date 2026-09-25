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
    var generation: Int32 = 0
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
    let midiGeneration: UnsafeMutablePointer<Int32>

    init() {
        let n = SynthRenderer.maxVoices + SynthRenderer.maxMIDINotes
        phase = .allocate(capacity: n); phase.initialize(repeating: 0, count: n)
        lfo = .allocate(capacity: n); lfo.initialize(repeating: 0, count: n)
        freq = .allocate(capacity: n); freq.initialize(repeating: 0, count: n)
        vol = .allocate(capacity: n); vol.initialize(repeating: 0, count: n)
        midiGeneration = .allocate(capacity: SynthRenderer.maxMIDINotes)
        midiGeneration.initialize(repeating: 0, count: SynthRenderer.maxMIDINotes)
    }

    deinit {
        phase.deallocate(); lfo.deallocate(); freq.deallocate(); vol.deallocate(); midiGeneration.deallocate()
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
        let parameters = midiParams[slot]
        midiParams[slot].active = false
        midiParams[slot].frequency = 440 * powf(2, (Float(note) - 69) / 12)
        midiParams[slot].velocity = max(0, min(1, velocity))
        midiParams[slot].pitchBend = parameters.pitchBend
        midiParams[slot].modulation = parameters.modulation
        midiParams[slot].pressure = 1
        midiParams[slot].selectedVoice = selectedVoice
        midiParams[slot].generation = parameters.generation &+ 1
        midiParams[slot].active = true
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
        let midiGeneration = state.midiGeneration
        let count = SynthRenderer.maxVoices
        let master: Float = 0.25
        let twoPi = Float.pi * 2
        let smoothing: Float = 0.002
        var midiNoteNormalization: Float = 1
        return AVAudioSourceNode { [self] _, _, frameCount, audioBufferList -> OSStatus in
            _ = self   // keeps the renderer (and its params) alive while the node exists
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let left = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = abl[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            // Snapshot the fixed-size settings once per buffer. MIDI note counts
            // include release tails so chord level changes don't step on key-up.
            let activeMIDINotes = max(1, (0..<SynthRenderer.maxMIDINotes).reduce(0) { total, slot in
                let noteState = count + slot
                return total + ((midiParams[slot].active || state.vol[noteState] > 0.0001) ? 1 : 0)
            })
            let enabledBaseVoices = max(1, (0..<count).reduce(0) { $0 + (params[$1].enabled ? 1 : 0) })
            let targetMIDINoteNormalization = 1 / Float(activeMIDINotes)

            for frame in 0..<Int(frameCount) {
                // Smooth polyphony gain: changing the divisor on the exact
                // note-on sample creates an audible transient during chords.
                midiNoteNormalization += (targetMIDINoteNormalization - midiNoteNormalization) * smoothing
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
                    let phaseStep = min(0.5, Float(state.freq[v] / Float(sampleRate)))
                    let shaped: Float
                    switch p.wave {
                    case 1:
                        let shifted = ph < 0.5 ? ph + 0.5 : ph - 0.5
                        shaped = (ph < 0.5 ? 1 : -1) + polyBLEP(ph, step: phaseStep) - polyBLEP(shifted, step: phaseStep)
                    case 2: shaped = 4 * abs(ph - 0.5) - 1
                    case 3: shaped = 2 * ph - 1 - polyBLEP(ph, step: phaseStep)
                    default: shaped = sinf(twoPi * ph)
                    }
                    let s = highFrequencyBlend(shaped, phase: ph, phaseStep: phaseStep, twoPi: twoPi)

                    let position = min(max(p.pan + p.sweep * sinf(twoPi * Float(state.lfo[v])), -1), 1)
                    let angle = (position + 1) * Float.pi / 4  // equal-power pan
                    let gain = s * state.vol[v] / Float(enabledBaseVoices)
                    l += gain * cosf(angle)
                    r += gain * sinf(angle)
                }
                for noteSlot in 0..<SynthRenderer.maxMIDINotes {
                    let note = midiParams[noteSlot]
                    let stateIndex = count + noteSlot
                    let targetFrequency = min(note.frequency * note.pitchBend,
                                              Float(sampleRate) * 0.45)
                    if midiGeneration[noteSlot] != note.generation {
                        midiGeneration[noteSlot] = note.generation
                        state.phase[stateIndex] = 0
                        state.freq[stateIndex] = targetFrequency
                        state.vol[stateIndex] = 0
                    }
                    let targetVol: Float = note.active ? note.velocity : 0
                    if targetVol == 0 && state.vol[stateIndex] < 0.00001 {
                        state.vol[stateIndex] = 0
                        continue
                    }
                    state.vol[stateIndex] += (targetVol - state.vol[stateIndex]) * smoothing
                    state.lfo[stateIndex] += 5 / sampleRate
                    if state.lfo[stateIndex] >= 1 { state.lfo[stateIndex] -= 1 }
                    let vibrato = 1 + sinf(twoPi * Float(state.lfo[stateIndex])) * note.modulation * 0.004
                    let bentFrequency = min(note.frequency * note.pitchBend * vibrato,
                                            Float(sampleRate) * 0.45)
                    state.freq[stateIndex] = bentFrequency
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
                        let phaseStep = min(0.5, state.freq[stateIndex] / Float(sampleRate))
                        let shaped: Float
                        switch voice.wave {
                        case 1:
                            let shifted = phase < 0.5 ? phase + 0.5 : phase - 0.5
                            shaped = (phase < 0.5 ? 1 : -1) + polyBLEP(phase, step: phaseStep) - polyBLEP(shifted, step: phaseStep)
                        case 2: shaped = 4 * abs(phase - 0.5) - 1
                        case 3: shaped = 2 * phase - 1 - polyBLEP(phase, step: phaseStep)
                        default: shaped = sinf(twoPi * phase)
                        }
                        let wave = highFrequencyBlend(shaped, phase: phase, phaseStep: phaseStep, twoPi: twoPi)
                        let position = min(max(voice.pan, -1), 1)
                        let angle = (position + 1) * Float.pi / 4
                        let gain = wave * state.vol[stateIndex] * note.pressure * voice.volume
                            * midiNoteNormalization / Float(enabledMIDIVoices)
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

    /// Reduces discontinuity aliasing in the square and saw oscillators.
    private func polyBLEP(_ phase: Float, step: Float) -> Float {
        guard step > 0 else { return 0 }
        if phase < step {
            let t = phase / step
            return t + t - t * t - 1
        }
        if phase > 1 - step {
            let t = (phase - 1) / step
            return t * t + t + t + 1
        }
        return 0
    }

    /// Rolls harmonics toward a sine near Nyquist to avoid harsh aliasing on high MIDI notes.
    private func highFrequencyBlend(_ shaped: Float, phase: Float, phaseStep: Float, twoPi: Float) -> Float {
        let blend = min(1, max(0, (phaseStep - 0.12) / 0.10))
        guard blend > 0 else { return shaped }
        let sine = sinf(twoPi * phase)
        return shaped + (sine - shaped) * blend
    }
}
