import AVFoundation

final class DelayEffect: EffectModule {
    private let delay: AVAudioUnitDelay

    init() {
        let d = AVAudioUnitDelay()
        delay = d
        super.init(key: "delay", name: "Delay", unit: d, parameters: [
            EffectParameter(id: "time", name: "Time", range: 0.01...2, value: 0.3, unit: " s"),
            EffectParameter(id: "feedback", name: "Feedback", range: -70...70, value: 30, unit: "%"),
            EffectParameter(id: "mix", name: "Mix", range: 0...100, value: 30, unit: "%"),
            EffectParameter(id: "tone", name: "Tone", range: 500...20000, value: 12000,
                            display: { String(format: "%.0f Hz", $0) })
        ])
        isEnabled = false
        apply()
    }

    override func apply() {
        delay.bypass = !isEnabled
        delay.delayTime = TimeInterval(value("time"))
        delay.feedback = value("feedback")
        delay.wetDryMix = value("mix")
        delay.lowPassCutoff = value("tone")
    }
}
