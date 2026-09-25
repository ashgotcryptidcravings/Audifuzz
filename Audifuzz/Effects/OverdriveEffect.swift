import AVFoundation

final class OverdriveEffect: EffectModule {
    private let dist: AVAudioUnitDistortion

    init() {
        let d = AVAudioUnitDistortion()
        d.loadFactoryPreset(.multiDistortedCubed)
        dist = d
        super.init(key: "overdrive", name: "Overdrive", unit: d, parameters: [
            EffectParameter(id: "drive", name: "Drive", range: -6...20, value: 6, unit: " dB"),
            EffectParameter(id: "mix", name: "Mix", range: 0...100, value: 60, unit: "%"),
            EffectParameter(id: "character", name: "Character", range: 1...6, value: 1,
                            display: { "Type \(Int($0.rounded()))" })
        ])
        apply()
    }

    override func apply() {
        dist.bypass = !isEnabled
        let presets: [AVAudioUnitDistortionPreset] = [.multiDistortedCubed, .multiDistortedSquared, .multiDistortedFunk, .drumsBitBrush, .multiBrokenSpeaker, .speechRadioTower, .speechCosmicInterference]
        dist.loadFactoryPreset(presets[max(0, min(presets.count - 1, Int(value("character").rounded()) - 1))])
        dist.preGain = value("drive")
        dist.wetDryMix = value("mix")
    }
}
