import AVFoundation

/// One adjustable knob on an effect.
struct EffectParameter: Identifiable {
    let id: String
    let name: String
    let range: ClosedRange<Float>
    let defaultValue: Float
    var value: Float

    init(id: String, name: String, range: ClosedRange<Float>, value: Float) {
        self.id = id
        self.name = name
        self.range = range
        self.defaultValue = value
        self.value = value
    }
}

/// Base class for every effect. Subclass it, wrap one AVAudioUnit,
/// and override `apply()` to push the current values into that unit.
class EffectModule: ObservableObject, Identifiable {
    let id = UUID()
    let key: String          // stable id used by presets, e.g. "overdrive"
    let name: String
    let unit: AVAudioUnit

    @Published var isEnabled: Bool = true { didSet { apply() } }
    @Published var parameters: [EffectParameter] { didSet { apply() } }

    init(key: String, name: String, unit: AVAudioUnit, parameters: [EffectParameter]) {
        self.key = key
        self.name = name
        self.unit = unit
        self.parameters = parameters
    }

    /// Override in subclasses. Call it once at the end of the subclass init.
    func apply() {}

    func value(_ parameterID: String) -> Float {
        parameters.first { $0.id == parameterID }?.value ?? 0
    }

    func reset() {
        for i in parameters.indices { parameters[i].value = parameters[i].defaultValue }
        isEnabled = true
    }
}
