import AVFoundation
import Foundation

final class FilterEffect: EffectModule {
    private let eq: AVAudioUnitEQ

    init() {
        let e = AVAudioUnitEQ(numberOfBands: 1)
        e.bands[0].filterType = .lowPass
        e.bands[0].bypass = false
        eq = e
        super.init(key: "filter", name: "Low-Pass Filter", unit: e, parameters: [
            // 0...1 mapped to 20 Hz...20 kHz on a log curve
            EffectParameter(id: "cutoff", name: "Cutoff", range: 0...1, value: 1)
        ])
        apply()
    }

    override func apply() {
        eq.bypass = !isEnabled
        eq.bands[0].frequency = 20 * Float(pow(1000.0, Double(value("cutoff"))))
    }
}
