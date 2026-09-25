import AVFoundation
import Foundation

final class FilterEffect: EffectModule {
    private let eq: AVAudioUnitEQ

    private static func hertz(_ v: Float) -> Float { 20 * Float(pow(1000.0, Double(v))) }

    init() {
        let e = AVAudioUnitEQ(numberOfBands: 1)
        e.bands[0].filterType = .lowPass
        e.bands[0].bypass = false
        eq = e
        super.init(key: "filter", name: "Low-Pass Filter", unit: e, parameters: [
            // 0...1 mapped to 20 Hz...20 kHz on a log curve
            EffectParameter(id: "cutoff", name: "Cutoff", range: 0...1, value: 1,
                            display: { v in String(format: "%.0f Hz", FilterEffect.hertz(v)) }),
            EffectParameter(id: "resonance", name: "Resonance / Q", range: 0.1...4, value: 1.0, unit: "×"),
            EffectParameter(id: "type", name: "Type", range: 1...3, value: 1,
                            display: { ["Low", "High", "Band"][max(0, min(2, Int($0.rounded()) - 1))] })
        ])
        apply()
    }

    override func apply() {
        eq.bypass = !isEnabled
        eq.bands[0].frequency = FilterEffect.hertz(value("cutoff"))
        eq.bands[0].bandwidth = value("resonance")
        switch Int(value("type").rounded()) {
        case 2: eq.bands[0].filterType = .highPass
        case 3: eq.bands[0].filterType = .bandPass
        default: eq.bands[0].filterType = .lowPass
        }
    }
}
