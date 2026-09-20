import AVFoundation

final class ReverbEffect: EffectModule {
    private let reverb: AVAudioUnitReverb

    init() {
        let r = AVAudioUnitReverb()
        r.loadFactoryPreset(.largeHall)
        reverb = r
        super.init(key: "reverb", name: "Reverb", unit: r, parameters: [
            EffectParameter(id: "mix", name: "Mix", range: 0...100, value: 25)
        ])
        isEnabled = false
        apply()
    }

    override func apply() {
        reverb.bypass = !isEnabled
        reverb.wetDryMix = value("mix")
    }
}
