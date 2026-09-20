import Foundation

struct EffectState: Codable {
    let key: String
    var enabled: Bool
    var values: [String: Float]
}

struct Preset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var effects: [EffectState]
}

/// Presets are tiny JSON files in the app's Documents folder.
enum PresetStore {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Presets", isDirectory: true)
    }

    static func save(_ preset: Preset) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(preset)
        try data.write(to: directory.appendingPathComponent("\(preset.name).json"))
    }

    static func loadAll() -> [Preset] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Preset.self, from: Data(contentsOf: $0)) }
    }
}
