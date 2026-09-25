import AVFoundation

struct SpatialLocation: Identifiable {
    let id: UUID
    var azimuth: Float
    var elevation: Float
    var distance: Float

    init(id: UUID = UUID(), azimuth: Float = 0, elevation: Float = 0, distance: Float = 2) {
        self.id = id
        self.azimuth = azimuth
        self.elevation = elevation
        self.distance = distance
    }
}

/// Uses AVAudioEnvironmentNode's native spatial renderer for one or more mono sources.
final class SpatialStage: ObservableObject {
    let sourceMixers = (0..<4).map { _ in AVAudioMixerNode() }
    let environment = AVAudioEnvironmentNode()
    var onRouteChange: (() -> Void)?

    @Published var isEnabled = false { didSet { if isEnabled != oldValue { onRouteChange?() } } }
    @Published var locations: [SpatialLocation] = [SpatialLocation()] {
        didSet { apply() }
    }
    @Published var reverb: Float = 0 { didSet { apply() } }

    init() {
        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
        environment.reverbParameters.level = 0
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance = 0.5
        environment.outputType = .headphones
        apply()
    }

    func addLocation() {
        guard locations.count < sourceMixers.count else { return }
        let source = locations.last ?? SpatialLocation()
        let nextAzimuth = source.azimuth + 35
        locations.append(SpatialLocation(azimuth: nextAzimuth > 180 ? nextAzimuth - 360 : nextAzimuth,
                                         elevation: source.elevation,
                                         distance: source.distance))
        onRouteChange?()
    }

    func removeLocation(_ id: UUID) {
        guard locations.count > 1 else { return }
        locations.removeAll { $0.id == id }
        onRouteChange?()
    }

    func updateLocation(_ id: UUID, _ update: (inout SpatialLocation) -> Void) {
        guard let index = locations.firstIndex(where: { $0.id == id }) else { return }
        update(&locations[index])
    }

    /// Let Apple's environment renderer choose the best algorithm for the active output.
    func apply() {
        environment.reverbParameters.level = reverb
        for (index, location) in locations.enumerated() where sourceMixers.indices.contains(index) {
            let azimuth = Double(location.azimuth) * .pi / 180
            let elevation = Double(location.elevation) * .pi / 180
            let distance = Double(location.distance)
            let mixer = sourceMixers[index]
            mixer.position = AVAudio3DPoint(
                x: Float(distance * sin(azimuth) * cos(elevation)),
                y: Float(distance * sin(elevation)),
                z: Float(-distance * cos(azimuth) * cos(elevation)))
            mixer.renderingAlgorithm = .auto
            mixer.reverbBlend = reverb
        }
    }
}
