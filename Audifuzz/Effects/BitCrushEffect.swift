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
            EffectParameter(id: "gain", name: "Gain", range: -6...20, value: 0, unit: " dB"),
            EffectParameter(id: "mix", name: "Mix", range: 0...100, value: 50, unit: "%"),
            EffectParameter(id: "mode", name: "Decimation", range: 1...4, value: 4,
                            display: { value in "Decim \(Int(value.rounded()))" })
        ])
        apply()
    }

    override func apply() {
        dist.bypass = !isEnabled
        let mode = Int(value("mode").rounded())
        let preset: AVAudioUnitDistortionPreset
        switch mode {
        case 1: preset = .multiDecimated1
        case 2: preset = .multiDecimated2
        case 3: preset = .multiDecimated3
        case 4: preset = .multiDecimated4
        default: preset = .multiDecimated4
        }
        dist.loadFactoryPreset(preset)
        dist.preGain = value("gain")
        dist.wetDryMix = value("mix")
    }
}
