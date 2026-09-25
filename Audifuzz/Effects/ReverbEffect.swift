import AVFoundation

final class ReverbEffect: EffectModule {
    private let reverb: AVAudioUnitReverb

    init() {
        let r = AVAudioUnitReverb()
        r.loadFactoryPreset(.largeHall)
        reverb = r
        super.init(key: "reverb", name: "Reverb", unit: r, parameters: [
            EffectParameter(id: "mix", name: "Mix", range: 0...100, value: 25, unit: "%"),
            EffectParameter(id: "room", name: "Room / Preset", range: 1...12, value: 5,
                            display: { "Preset \(Int($0.rounded()))" })
        ])
        isEnabled = false
        apply()
    }

    override func apply() {
        reverb.bypass = !isEnabled
        let presets: [AVAudioUnitReverbPreset] = [.smallRoom, .mediumRoom, .largeRoom, .mediumHall, .largeHall, .plate, .cathedral, .largeChamber, .largeRoom2, .mediumHall2, .mediumHall3, .largeHall2]
        reverb.loadFactoryPreset(presets[max(0, min(presets.count - 1, Int(value("room").rounded()) - 1))])
        reverb.wetDryMix = value("mix")
    }
}
