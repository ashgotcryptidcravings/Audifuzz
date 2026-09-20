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

/// Running state for one source node (phases, smoothed pitch/volume).
private final class VoiceState {
    let phase: UnsafeMutablePointer<Double>
    let lfo: UnsafeMutablePointer<Double>
    let freq: UnsafeMutablePointer<Float>
    let vol: UnsafeMutablePointer<Float>

    init() {
        let n = SynthRenderer.maxVoices
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
    private let params: UnsafeMutablePointer<VoiceParams>

    init() {
        params = .allocate(capacity: SynthRenderer.maxVoices)
        params.initialize(repeating: VoiceParams(), count: SynthRenderer.maxVoices)
    }

    deinit { params.deallocate() }

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

            for frame in 0..<Int(frameCount) {
                var l: Float = 0
                var r: Float = 0
                for v in 0..<count {
                    let p = params[v]
                    let targetVol: Float = p.enabled ? p.volume : 0
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
                    let gain = s * state.vol[v]
                    l += gain * cosf(angle)
                    r += gain * sinf(angle)
                }
                left[frame] = min(max(l * master, -1), 1)
                right[frame] = min(max(r * master, -1), 1)
            }
            return noErr
        }
    }
}
