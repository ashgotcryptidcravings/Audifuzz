import AVFoundation

/// Uses Apple's built-in decimation preset for now.
/// Swap for a custom bitcrusher render block later if you want full control.
final class BitCrushEffect: EffectModule {
    private let dist: AVAudioUnitDistortion

    init() {
        let d = AVAudioUnitDistortion()
        d.loadFactoryPreset(.multiDecimated4)
        dist = d
        super.init(key: "bitcrush", name: "Bit Crush", unit: d, parameters: [
            EffectParameter(id: "gain", name: "Gain", range: -6...20, value: 0),
            EffectParameter(id: "mix", name: "Mix", range: 0...100, value: 0)
        ])
        apply()
    }

    override func apply() {
        dist.bypass = !isEnabled
        dist.preGain = value("gain")
        dist.wetDryMix = value("mix")
    }
}
