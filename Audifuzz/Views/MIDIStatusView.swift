import SwiftUI

struct MIDIStatusView: View {
    @ObservedObject var midi: MIDIInputManager
    @ObservedObject var lab: SoundLabEngine
    @State private var lingeringNotes: [MIDIPressedNote] = []
    @State private var releaseGeneration = 0
    @State private var recentNoteAttacks: [TimeInterval] = []
    @State private var recentVelocity = 0
    @State private var attackGeneration = 0

    private var visibleNotes: [MIDIPressedNote] {
        midi.activeNotes.isEmpty ? lingeringNotes : midi.activeNotes
    }

    private var soundLevel: Double {
        guard !lab.waveform.isEmpty else { return 0 }
        let meanSquare = lab.waveform.reduce(0.0) { $0 + Double($1 * $1) } / Double(lab.waveform.count)
        return min(1, sqrt(meanSquare) * 4)
    }

    private var attackRate: Double { Double(recentNoteAttacks.count) / 1.5 }

    private var chordMood: MIDIChordMood {
        MIDIChordMood(notes: visibleNotes, velocity: recentVelocity,
                      attackRate: attackRate, soundLevel: soundLevel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("MIDI").font(.largeTitle.bold())
                    HStack(spacing: 7) {
                        Circle()
                            .fill(midi.isEnabled && !midi.activeNotes.isEmpty ? Color.green :
                                  (midi.isEnabled ? Color.orange : Color.secondary))
                            .frame(width: 8, height: 8)
                        Text(midi.isEnabled ? midi.connectionStatus : "MIDI input is off")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text(midi.currentDeviceName)
                        .font(.title3.weight(.semibold))
                    Picker("MIDI Instrument", selection: $midi.selectedInstrument) {
                        ForEach(Array(lab.midiInstrumentOptions.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                    Text(midi.lastActivityDescription)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                GeometryReader { geometry in
                    let diameter = min(min(geometry.size.width * 0.72, geometry.size.height - 28), 340)
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.18))
                                .frame(width: diameter + 36, height: diameter + 36)
                                .blur(radius: 14)
                            Circle()
                                .fill(Color.clear)
                                .modifier(AnimatedOrbFill(hue: chordMood.hue,
                                                         accentHue: chordMood.accentHue,
                                                         saturation: chordMood.saturation,
                                                         brightness: chordMood.brightness,
                                                         gradientAmount: chordMood.usesGradient ? 1 : 0))
                                .overlay {
                                    if chordMood.usesGradient {
                                        Circle().fill(
                                            RadialGradient(colors: [Color.white.opacity(0.34), .clear],
                                                           center: .init(x: 0.34, y: 0.28), startRadius: 1,
                                                           endRadius: diameter * 0.8)
                                        )
                                    }
                                }
                                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                                .frame(width: diameter, height: diameter)
                                .shadow(color: chordMood.glow.opacity(0.08 + chordMood.soundLevel * 0.58), radius: 18 + chordMood.soundLevel * 24)
                                .scaleEffect(0.92 + chordMood.soundLevel * 0.09 + min(0.06, chordMood.attackRate * 0.008))
                                .animation(.easeInOut(duration: 0.8), value: chordMood.signature)
                                .animation(.easeOut(duration: 0.16), value: chordMood.soundLevel)
                            VStack(spacing: 5) {
                                Text(visibleNotes.isEmpty ? "READY" : chordMood.moodLabel.uppercased())
                                    .font(.caption.weight(.bold))
                                    .tracking(1.6)
                                Text(visibleNotes.isEmpty ? "Play a key" : chordMood.noteSummary)
                                    .font(.caption.monospacedDigit())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundColor(.white.opacity(0.94))
                            .shadow(color: .black.opacity(0.55), radius: 5)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if !visibleNotes.isEmpty {
                            Text("LEVEL \(Int(chordMood.soundLevel * 100))%  ·  ATTACK \(String(format: "%.1f", chordMood.attackRate))/s\(midi.activeNotes.isEmpty ? "  ·  TAIL" : "")")
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 6)
                        }
                    }
                }
                .frame(height: 360)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Hardware capabilities", systemImage: "pianokeys")
                        .font(.headline)
                    ForEach(capabilityLines, id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if !visibleNotes.isEmpty {
                        Text("Velocity is the MIDI value reported by the controller; it can’t directly measure physical force.")
                        Text("Please note that this software is currently being built around the Alesis V25 MIDI Keyboard.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .card()
            }
            .padding()
        }
        .onAppear { midi.refreshDevices() }
        .onReceive(midi.$activeNotes) { notes in
            guard notes.isEmpty else {
                releaseGeneration += 1
                lingeringNotes = notes
                return
            }
            let generation = releaseGeneration + 1
            releaseGeneration = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                guard generation == releaseGeneration, midi.activeNotes.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.55)) { lingeringNotes = [] }
            }
        }
        .onReceive(midi.activity) { event in
            guard event.kind == .noteOn else { return }
            let now = ProcessInfo.processInfo.systemUptime
            recentNoteAttacks = recentNoteAttacks.filter { now - $0 < 1.5 } + [now]
            recentVelocity = Int(event.data2)
            attackGeneration += 1
            let generation = attackGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                guard generation == attackGeneration else { return }
                recentNoteAttacks.removeAll()
                recentVelocity = 0
            }
        }
    }

    private var capabilityLines: [String] {
        let model = midi.currentDeviceName.lowercased()
        if model.contains("alesis") && model.contains("v25") && model.contains("mkii") {
            return [
                "25 velocity-sensitive keys with octave and transpose access",
                "Pitch-bend and modulation wheels",
                "8 velocity-sensitive pads and 4 assignable knobs",
                "Built-in arpeggiator, note repeat, and sustain-pedal input"
            ]
        }
        if model.contains("alesis") && model.contains("v25") {
            return [
                "25 velocity-sensitive keys; Octave Up/Down access the full MIDI note range",
                "Pitch-bend wheel and modulation wheel (CC 1 by default)",
                "4 assignable knobs, 4 assignable buttons, and 8 velocity-sensitive pads",
                "Optional sustain-pedal input; V Editor can reassign supported controls"
            ]
        }
        return [
            "MIDI note and velocity input",
            "Pitch bend, control changes, program changes, and aftertouch when sent",
            "Connected controls are reported as you move or press them"
        ]
    }
}

private struct MIDIChordMood {
    let glow: Color
    let hue: Double
    let accentHue: Double
    let saturation: Double
    let brightness: Double
    let moodLabel: String
    let noteSummary: String
    let signature: String
    let usesGradient: Bool
    let soundLevel: Double
    let attackRate: Double

    init(notes: [MIDIPressedNote], velocity: Int, attackRate: Double, soundLevel: Double) {
        self.soundLevel = soundLevel
        self.attackRate = attackRate
        guard !notes.isEmpty else {
            hue = 0.58
            accentHue = 0.58
            saturation = 0.32
            brightness = 0.36
            glow = .blue
            moodLabel = "Ready"
            noteSummary = ""
            signature = "rest"
            usesGradient = false
            return
        }

        let ordered = notes.sorted { $0.note < $1.note }
        let pitchClasses = ordered.map { Int($0.note) % 12 }
        let uniquePitchClasses = Array(Set(pitchClasses)).sorted()
        let dissonance = Self.dissonance(of: uniquePitchClasses)
        let chromaticDensity = uniquePitchClasses.count >= 8
        let denseTension = uniquePitchClasses.count >= 6 && dissonance >= 0.22
        let murky = uniquePitchClasses.count >= 3 &&
            (dissonance >= 0.38 || chromaticDensity || denseTension)
        let sharpLeaning = Self.prefersSharps(pitchClasses)
        let baseHue = sharpLeaning ? 0.055 : 0.60
        let meanPitchClass = Double(uniquePitchClasses.reduce(0, +)) / Double(max(1, uniquePitchClasses.count))
        let noteHue = Self.wrapHue(baseHue + meanPitchClass / 12 * 0.16)
        hue = murky ? 0.105 : noteHue
        accentHue = murky ? 0.16 : Self.wrapHue(baseHue + Double(uniquePitchClasses.last ?? 0) / 12 * 0.16)
        usesGradient = uniquePitchClasses.count > 1
        let loudness = min(1, max(0, Double(velocity) / 127))
        saturation = murky ? 0.36 : min(0.92, 0.58 + loudness * 0.28 + soundLevel * 0.12)
        brightness = murky ? 0.43 : min(0.94, 0.44 + loudness * 0.25 + soundLevel * 0.25)
        glow = Color(hue: hue, saturation: saturation, brightness: brightness)
        if murky {
            moodLabel = "Murky"
        } else if attackRate >= 5 {
            moodLabel = "Rapid · " + (sharpLeaning ? "Sharp" : "Flat")
        } else {
            moodLabel = sharpLeaning ? "Sharp-leaning" : "Flat-leaning"
        }
        noteSummary = ordered.map { Self.noteName(Int($0.note)) }.joined(separator: " · ")
        signature = uniquePitchClasses.map(String.init).joined(separator: ",") + "-\(murky)-\(Int(attackRate.rounded()))"
    }

    private static func wrapHue(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }

    private static func noteName(_ note: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[note % 12] + String(note / 12 - 1)
    }

    private static func dissonance(of notes: [Int]) -> Double {
        guard notes.count > 1 else { return 0 }
        var total = 0.0
        var pairs = 0
        for first in 0..<(notes.count - 1) {
            for second in (first + 1)..<notes.count {
                let distance = abs(notes[first] - notes[second]) % 12
                let interval = min(distance, 12 - distance)
                let weight: Double
                switch interval {
                case 1: weight = 1.0
                case 2: weight = 0.58
                case 6: weight = 1.0
                default: weight = 0.08
                }
                total += weight
                pairs += 1
            }
        }
        return total / Double(max(1, pairs))
    }

    /// Infers a likely notation preference from the chord's best-fitting key.
    /// MIDI note numbers themselves don't distinguish enharmonic spellings.
    private static func prefersSharps(_ notes: [Int]) -> Bool {
        let classes = Set(notes)
        let major = [0, 2, 4, 5, 7, 9, 11]
        let minor = [0, 2, 3, 5, 7, 8, 10]
        let sharpKeys: [Int: Int] = [7: 1, 2: 2, 9: 3, 4: 4, 11: 5, 6: 6, 1: 7]
        let flatKeys: [Int: Int] = [5: -1, 10: -2, 3: -3, 8: -4, 1: -5, 6: -6, 11: -7]
        var bestScore = -Double.infinity
        var bestPreference = 0
        for tonic in 0..<12 {
            for scale in [major, minor] {
                let scaleNotes = Set(scale.map { (tonic + $0) % 12 })
                let inScale = classes.filter { scaleNotes.contains($0) }.count
                let outside = classes.count - inScale
                let bassBonus = notes.first == tonic ? 0.3 : 0
                let score = Double(inScale) - Double(outside) * 1.1 + bassBonus
                if score > bestScore {
                    bestScore = score
                    bestPreference = sharpKeys[tonic] ?? flatKeys[tonic] ?? 0
                }
            }
        }
        return bestPreference >= 0
    }
}

/// Keeps a single held pitch a single hue, while chord colors blend smoothly.
private struct AnimatedOrbFill: AnimatableModifier {
    var hue: Double
    var accentHue: Double
    var saturation: Double
    var brightness: Double
    var gradientAmount: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, Double>>>> {
        get { AnimatablePair(hue, AnimatablePair(accentHue, AnimatablePair(saturation, AnimatablePair(brightness, gradientAmount)))) }
        set {
            hue = newValue.first
            accentHue = newValue.second.first
            saturation = newValue.second.second.first
            brightness = newValue.second.second.second.first
            gradientAmount = newValue.second.second.second.second
        }
    }

    func body(content: Content) -> some View {
        content.overlay {
            let primary = Color(hue: hue, saturation: saturation, brightness: brightness)
            let accent = Color(hue: accentHue, saturation: saturation, brightness: brightness * 0.94)
            ZStack {
                Circle().fill(primary)
                Circle().fill(AngularGradient(
                    gradient: Gradient(colors: [primary, accent, primary]),
                    center: .center
                )).opacity(gradientAmount)
            }
        }
    }
}
