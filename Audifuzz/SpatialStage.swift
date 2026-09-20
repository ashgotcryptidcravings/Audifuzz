import AVFoundation

/// 3D spatializer. Audio is folded to mono, then placed around the listener
/// with Apple's HRTF renderer (best on headphones).
/// Direction: 0 = front, +90 = right, -90 = left, 180 = behind.
final class SpatialStage: ObservableObject {
    let mixer = AVAudioMixerNode()               // converts the chain to mono
    let environment = AVAudioEnvironmentNode()
    var onRouteChange: (() -> Void)?

    @Published var isEnabled = false { didSet { if isEnabled != oldValue { onRouteChange?() } } }
    @Published var azimuth: Float = 0 { didSet { apply() } }       // degrees
    @Published var elevation: Float = 0 { didSet { apply() } }     // degrees
    @Published var distance: Float = 2 { didSet { apply() } }      // meters
    @Published var reverb: Float = 0 { didSet { apply() } }        // percent

    init() {
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
        environment.reverbParameters.level = 0
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 0.5
        apply()
    }

    /// Push the current settings into the audio nodes.
    func apply() {
        let az = Double(azimuth) * .pi / 180
        let el = Double(elevation) * .pi / 180
        let d = Double(distance)
        mixer.position = AVAudio3DPoint(
            x: Float(d * sin(az) * cos(el)),
            y: Float(d * sin(el)),
            z: Float(-d * cos(az) * cos(el)))
        mixer.renderingAlgorithm = .HRTFHQ
        mixer.reverbBlend = reverb
    }
}
