import AVFoundation

final class ToneEQEffect: EffectModule {
    private let eq: AVAudioUnitEQ

    init() {
        let unit = AVAudioUnitEQ(numberOfBands: 3)
        unit.bands[0].filterType = .lowShelf
        unit.bands[1].filterType = .parametric
        unit.bands[2].filterType = .highShelf
        unit.bands[0].frequency = 120
        unit.bands[1].frequency = 1000
        unit.bands[2].frequency = 8000
        eq = unit
        super.init(key: "toneEQ", name: "3-Band EQ", unit: unit, parameters: [
            EffectParameter(id: "low", name: "Low", range: -18...18, value: 0, unit: " dB"),
            EffectParameter(id: "mid", name: "Mid", range: -18...18, value: 0, unit: " dB"),
            EffectParameter(id: "high", name: "High", range: -18...18, value: 0, unit: " dB")
        ])
        apply()
    }

    override func apply() {
        eq.bypass = !isEnabled
        eq.bands[0].gain = value("low")
        eq.bands[1].gain = value("mid")
        eq.bands[2].gain = value("high")
    }
}
