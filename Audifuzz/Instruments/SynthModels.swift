import Foundation

enum Wave: Int, CaseIterable, Identifiable {
    case round, square, triangle, saw
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .round: return "Round"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .saw: return "Saw"
        }
    }
}

/// One "instrument": a single wave with its own pitch and left/right placement.
struct Voice: Identifiable {
    let id = UUID()
    var enabled = true
    var frequency: Float = 440     // Hz
    var wave: Wave = .round
    var volume: Float = 0.6        // 0...1
    var pan: Float = 0             // -1 (left ear) ... +1 (right ear)
    var sweep: Float = 0           // 0...1, how far the pan swings around its center
    var sweepRate: Float = 1       // Hz, how fast it swings
}

func noteName(_ frequency: Float) -> String {
    guard frequency > 0 else { return "" }
    let midi = Int((69 + 12 * log2(Double(frequency) / 440)).rounded())
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return names[((midi % 12) + 12) % 12] + String(midi / 12 - 1)
}
