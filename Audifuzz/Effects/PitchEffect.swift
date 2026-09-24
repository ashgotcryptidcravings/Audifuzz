import AVFoundation

final class PitchEffect: EffectModule {
    private let timePitch: AVAudioUnitTimePitch

    init() {
        let t = AVAudioUnitTimePitch()
        timePitch = t
        super.init(key: "pitch", name: "Pitch / Speed", unit: t, parameters: [
            EffectParameter(id: "pitch", name: "Pitch", range: -2400...2400, value: 0, unit: " ¢"), // cents
            EffectParameter(id: "rate", name: "Speed", range: 0.5...2, value: 1, unit: "×")
        ])
        isEnabled = false
        apply()
    }

    override func apply() {
        timePitch.bypass = !isEnabled
        timePitch.pitch = value("pitch")
        timePitch.rate = value("rate")
    }
}
