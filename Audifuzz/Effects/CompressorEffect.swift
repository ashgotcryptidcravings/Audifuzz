import AVFoundation
import AudioToolbox

final class CompressorEffect: EffectModule {
    private let dynamics: AVAudioUnitEffect

    init() {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let unit = AVAudioUnitEffect(audioComponentDescription: description)
        dynamics = unit
        super.init(key: "compressor", name: "Compressor / Limiter", unit: unit, parameters: [
            EffectParameter(id: "threshold", name: "Threshold", range: -40...0, value: -12, unit: " dB"),
            EffectParameter(id: "headroom", name: "Headroom", range: 0...20, value: 5, unit: " dB"),
            EffectParameter(id: "attack", name: "Attack", range: 0.001...0.2, value: 0.01, unit: " s"),
            EffectParameter(id: "release", name: "Release", range: 0.01...1, value: 0.1, unit: " s")
        ])
        apply()
    }

    override func apply() {
        dynamics.bypass = !isEnabled
        AudioUnitSetParameter(dynamics.audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, value("threshold"), 0)
        AudioUnitSetParameter(dynamics.audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, value("headroom"), 0)
        AudioUnitSetParameter(dynamics.audioUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, value("attack"), 0)
        AudioUnitSetParameter(dynamics.audioUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, value("release"), 0)
        AudioUnitSetParameter(dynamics.audioUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
    }
}
