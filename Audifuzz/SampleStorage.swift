import Foundation

/// Where recorded and saved samples live (the app's Documents/Samples folder).
enum SampleStorage {
    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func newURL(prefix: String, ext: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return directory.appendingPathComponent("\(prefix)-\(f.string(from: Date())).\(ext)")
    }

    static func list() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func date(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        }
        return urls
            .filter { ["wav", "caf", "m4a", "aif"].contains($0.pathExtension.lowercased()) }
            .sorted { date($0) > date($1) }
    }
}
