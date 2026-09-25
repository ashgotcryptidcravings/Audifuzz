import AVFoundation
import Foundation

/// Original starter sounds generated locally so the app ships with usable audio without downloads.
enum BuiltInSoundLibrary {
    struct Entry: Identifiable {
        let name: String
        let symbol: String
        let key: String?
        let url: URL?
        let isPlaceholder: Bool

        var id: String { name }
    }

    struct Details {
        let duration: TimeInterval
        let channels: AVAudioChannelCount
        let bitrate: Int
        let key: String?
        let dateAdded: Date
    }

    struct Sound {
        let name: String
        let samples: (Double) -> Float
    }

    private static let sampleRate = 44100
    private static let duration = 3

    static let names = ["Audifuzz Siren.wav", "Audifuzz 505.wav", "Audifuzz WahWhine.wav"]
    static let placeholderNames = (1...10).map { String(format: "Starter Slot %02d.wav", $0) }

    static var entries: [Entry] {
        var installed: [Entry] = [
            (names[0], "waveform", "A2"),
            (names[1], "pianokeys", "A3"),
            (names[2], "waveform.path.ecg", nil)
        ].compactMap { name, symbol, key in
            let url = SampleStorage.directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Entry(name: name, symbol: symbol, key: key, url: url, isPlaceholder: false)
        }

        if let url = Bundle.main.url(forResource: "DanganronpaIntro", withExtension: "mp3") {
            installed.append(Entry(
                name: url.lastPathComponent,
                symbol: "music.note.list",
                key: nil,
                url: url,
                isPlaceholder: false
            ))
        }

        installed.append(contentsOf: placeholderNames.map { name in
            let resourceName = (name as NSString).deletingPathExtension
            if let url = bundledAudioURL(for: resourceName) {
                return Entry(name: url.lastPathComponent, symbol: "waveform", key: nil, url: url, isPlaceholder: false)
            }
            return Entry(name: name, symbol: "waveform.badge.plus", key: nil, url: nil, isPlaceholder: true)
        })
        return installed
    }

    static func install() {
        let sounds: [Sound] = [
            Sound(name: names[0]) { time in
                let frequency = 110.0 + 55.0 * sin(2.0 * .pi * 0.4 * time)
                let phase = 2.0 * .pi * frequency * time
                let pulse = sin(phase) > 0 ? 0.8 : -0.8
                return Float(pulse * envelope(time))
            },
            Sound(name: names[1]) { time in
                let carrier = sin(2.0 * .pi * 220.0 * time)
                let shimmer = sin(2.0 * .pi * 331.0 * time) * 0.25
                return Float((carrier * 0.55 + shimmer) * envelope(time))
            },
            Sound(name: names[2]) { time in
                let noise = sin(2.0 * .pi * 1733.0 * time) * sin(2.0 * .pi * 2.7 * time)
                let grit = sin(2.0 * .pi * 311.0 * time) * 0.2
                return Float((noise * 0.45 + grit) * envelope(time))
            }
        ]

        for sound in sounds {
            let url = SampleStorage.directory.appendingPathComponent(sound.name)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try writeWAV(to: url, sample: sound.samples)
            } catch {
                print("[BuiltInSoundLibrary] FAILURE: Could not install \(sound.name): \(error.localizedDescription)")
            }
        }
    }

    static func isBuiltIn(_ url: URL) -> Bool {
        names.contains(url.lastPathComponent)
    }

    private static func bundledAudioURL(for resourceName: String) -> URL? {
        for fileExtension in ["mp3", "wav", "m4a", "aif", "caf"] {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) {
                return url
            }
        }
        return nil
    }

    static func details(for entry: Entry) -> Details? {
        do {
            guard let url = entry.url else { return nil }
            let file = try AVAudioFile(forReading: url)
            let format = file.fileFormat
            let bitDepth = (format.settings[AVLinearPCMBitDepthKey] as? Int) ?? 16
            let bitrate = Int(format.sampleRate * Double(bitDepth) * Double(format.channelCount))
            let dateAdded = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return Details(
                duration: Double(file.length) / format.sampleRate,
                channels: format.channelCount,
                bitrate: bitrate,
                key: entry.key,
                dateAdded: dateAdded
            )
        } catch {
            print("[BuiltInSoundLibrary] FAILURE: Could not inspect \(entry.name): \(error.localizedDescription)")
            return nil
        }
    }

    private static func envelope(_ time: Double) -> Double {
        min(1.0, time * 20.0) * min(1.0, (Double(duration) - time) * 20.0)
    }

    private static func writeWAV(to url: URL, sample: (Double) -> Float) throws {
        let frameCount = sampleRate * duration
        var pcm = [Int16](repeating: 0, count: frameCount * 2)
        for frame in 0..<frameCount {
            let value = Int16(max(-1, min(1, sample(Double(frame) / Double(sampleRate)))) * Float(Int16.max))
            pcm[frame * 2] = value
            pcm[frame * 2 + 1] = value
        }
        let audio = pcm.withUnsafeBytes { Data($0) }

        var header = Data()
        header.append(contentsOf: Data("RIFF".utf8))
        appendUInt32(&header, UInt32(36 + audio.count))
        header.append(contentsOf: Data("WAVEfmt ".utf8))
        appendUInt32(&header, 16)
        appendUInt16(&header, 1)
        appendUInt16(&header, 2)
        appendUInt32(&header, UInt32(sampleRate))
        appendUInt32(&header, UInt32(sampleRate * 4))
        appendUInt16(&header, 4)
        appendUInt16(&header, 16)
        header.append(contentsOf: Data("data".utf8))
        appendUInt32(&header, UInt32(audio.count))
        try (header + audio).write(to: url, options: .atomic)
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
    }
}
