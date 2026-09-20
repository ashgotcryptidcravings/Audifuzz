import AVFoundation

final class OverdriveEffect: EffectModule {
    private let dist: AVAudioUnitDistortion

    init() {
        let d = AVAudioUnitDistortion()
        d.loadFactoryPreset(.multiDistortedCubed)
        dist = d
        super.init(key: "overdrive", name: "Overdrive", unit: d, parameters: [
            EffectParameter(id: "drive", name: "Drive", range: -6...20, value: 6),
            EffectParameter(id: "mix", name: "Mix", range: 0...100, value: 60)
        ])
        apply()
    }

    override func apply() {
        dist.bypass = !isEnabled
        dist.preGain = value("drive")
        dist.wetDryMix = value("mix")
    }
}
