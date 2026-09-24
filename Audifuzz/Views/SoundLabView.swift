import SwiftUI

/// Second tab: build a sound from stacked waves, shape it with the equalizer,
/// then save it or send it to the Editor tab as a sample.
struct SoundLabView: View {
    @ObservedObject var lab: SoundLabEngine
    var onUseSample: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Sound Lab").font(.largeTitle.bold())
                controls

                ForEach(Array(lab.voices.enumerated()), id: \.element.id) { index, voice in
                    VoiceCardView(
                        voice: lab.binding(for: voice.id),
                        index: index,
                        canRemove: lab.voices.count > 1,
                        onRemove: { lab.removeVoice(voice.id) })
                }

                Button("Add instrument") { lab.addVoice() }
                    .buttonStyle(.bordered)
                    .disabled(lab.voices.count >= SynthRenderer.maxVoices)

                EqualizerCardView(lab: lab)
                samplesList
            }
            .padding()
        }
        .onAppear { lab.refreshSamples() }
        .onDisappear { lab.stopPreview() }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                Button(lab.isPlaying ? "Stop" : "Play") { lab.togglePlay() }
                Button("Save Sample") { lab.saveSample() }
                    .disabled(lab.isSaving)
                Dial(title: "Length", value: $lab.duration, range: 1...10, unit: " s", size: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let message = lab.statusMessage {
                Text(message).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private var samplesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved samples").font(.headline)
            if lab.samples.isEmpty {
                Text("Nothing saved yet.").font(.footnote).foregroundColor(.secondary)
            }
            ForEach(lab.samples, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent).font(.footnote).lineLimit(1)
                    Spacer()
                    Button("Use in Editor") { onUseSample(url) }
                    Button { lab.deleteSample(url) } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.borderless)
            }
        }
        .card()
    }
}

struct VoiceCardView: View {
    @Binding var voice: Voice
    let index: Int
    let canRemove: Bool
    let onRemove: () -> Void

    private func panText(_ v: Float) -> String {
        if abs(v) < 0.02 { return "Center" }
        return v < 0 ? "L \(Int(-v * 100))%" : "R \(Int(v * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Instrument \(index + 1)", isOn: $voice.enabled)
                    .font(.headline)
                Spacer()
                if canRemove {
                    Button { onRemove() } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }

            Picker("Shape", selection: $voice.wave) {
                ForEach(Wave.allCases) { w in
                    Text(w.label).tag(w)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                Dial(title: "Pitch", value: $voice.frequency, range: 20...5000, isLog: true, size: 64,
                     format: { "\(Int($0.rounded())) Hz\n\(noteName($0))" })
                Dial(title: "Volume", value: $voice.volume, range: 0...1,
                     format: { "\(Int($0 * 100))%" })
                Dial(title: "Ear", value: $voice.pan, range: -1...1, format: panText)
                Dial(title: "Sweep", value: $voice.sweep, range: 0...1,
                     format: { "\(Int($0 * 100))%" })
                Dial(title: "Sweep speed", value: $voice.sweepRate, range: 0.1...10, unit: " Hz")
            }
        }
        .card()
    }
}

struct EqualizerCardView: View {
    @ObservedObject var lab: SoundLabEngine
    private let labels = ["60", "250", "1k", "4k", "12k"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equalizer").font(.headline)
            
            HStack(spacing: 20) {
                ForEach(0..<labels.count, id: \.self) { i in
                    EQFader(
                        label: labels[i],
                        value: Binding(
                            get: { lab.eqGains[i] },
                            set: { lab.eqGains[i] = $0 }
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .card()
    }
}

struct EQFader: View {
    let label: String
    @Binding var value: Float
    var range: ClosedRange<Float> = -18...18

    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%+.0f", value))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(height: 14)

            GeometryReader { geo in
                let height = geo.size.height
                let percentage = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                let thumbY = height * (1 - percentage)

                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 4)
                        .cornerRadius(2)
                        .frame(maxHeight: .infinity)
                        .position(x: geo.size.width / 2, y: height / 2)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 12, height: 1)
                        .position(x: geo.size.width / 2, y: height * 0.5)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 12)
                        .position(x: geo.size.width / 2, y: thumbY)
                        .shadow(radius: 1)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { valueGesture in
                            let dragY = valueGesture.location.y
                            let clampedY = min(max(0, dragY), height)
                            let newPct = 1.0 - (clampedY / height)
                            let newValue = range.lowerBound + Float(newPct) * (range.upperBound - range.lowerBound)
                            value = min(max(range.lowerBound, newValue), range.upperBound)
                        }
                )
            }
            .frame(width: 32, height: 130)

            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
