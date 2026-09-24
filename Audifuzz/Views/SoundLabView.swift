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
        VStack(alignment: .leading, spacing: 10) {
            Text("Equalizer").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 12) {
                ForEach(0..<labels.count, id: \.self) { i in
                    Dial(title: labels[i],
                         value: Binding(get: { lab.eqGains[i] }, set: { lab.eqGains[i] = $0 }),
                         range: -18...18, size: 48,
                         format: { String(format: "%+.0f dB", $0) })
                }
            }
        }
        .card()
    }
}
