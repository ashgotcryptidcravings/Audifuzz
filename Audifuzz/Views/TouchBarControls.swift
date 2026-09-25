import SwiftUI

#if os(macOS)
/// Page-aware controls shown in the MacBook Pro Touch Bar.
struct TouchBarControls: View {
    @ObservedObject var manager: AudioEngineManager
    @ObservedObject var lab: SoundLabEngine
    @ObservedObject var spatial: SpatialStage
    @Binding var page: Int
    @Binding var selectedVoiceIndex: Int
    @Binding var scopeMode: Int
    @Binding var selectedSpatialLocationID: UUID?
    @Binding var selectedLibraryURL: URL?
    var addSelectedSample: () -> Void

    private var selectedVoice: Binding<Voice>? {
        guard lab.voices.indices.contains(selectedVoiceIndex) else { return nil }
        return lab.binding(for: lab.voices[selectedVoiceIndex].id)
    }

    private var selectedSpatialLocation: SpatialLocation? {
        spatial.locations.first(where: { $0.id == selectedSpatialLocationID }) ?? spatial.locations.first
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Label(isAnythingPlaying ? "Pause" : "Play",
                      systemImage: isAnythingPlaying ? "pause.fill" : "play.fill")
            }

            Divider().frame(height: 28)

            switch page {
            case 0:
                Button { manager.randomize() } label: { Label("Randomize", systemImage: "shuffle") }
                Button { manager.resetAll() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                Button {
                    manager.isMicLive ? manager.stopMic() : manager.setSource(.mic)
                } label: {
                    Label(manager.isMicLive ? "Stop Mic" : "Microphone", systemImage: "mic.fill")
                }
            case 1:
                synthSpaceControls
            case 2:
                spatialControls
            case 3:
                equalizerControls
            case 4:
                VStack(spacing: 2) {
                    Text(scopeLabels.indices.contains(scopeMode) ? scopeLabels[scopeMode] : "Waveform").font(.caption)
                    Slider(value: scopeModeBinding, in: 0...2, step: 1)
                        .frame(width: 250)
                    Text("Waveform     3D     Lissajous").font(.caption2).foregroundColor(.secondary)
                }
            case 5:
                if selectedLibraryURL != nil {
                    Button(action: addSelectedSample) {
                        Label("Add to Editor", systemImage: "slider.horizontal.3")
                    }
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var synthSpaceControls: some View {
        if !lab.voices.isEmpty {
            Picker("Instrument", selection: $selectedVoiceIndex) {
                ForEach(Array(lab.voices.enumerated()), id: \.element.id) { index, _ in
                    Text("Instrument \(index + 1)").tag(index)
                }
            }
            .frame(width: 130)

            if let voice = selectedVoice {
                VStack(spacing: 2) {
                    Text(voice.wrappedValue.wave.label).font(.caption)
                    Slider(value: waveBinding(voice.wave), in: 0...3, step: 1)
                        .frame(width: 220)
                    Text("Round     Square     Triangle     Saw").font(.caption2).foregroundColor(.secondary)
                }

                touchSlider("Pitch", value: frequencyBinding(voice.frequency), range: log2(20)...log2(5000), width: 150)
                touchSlider("Volume", value: floatAsDouble(voice.volume), range: 0...1, width: 120)
                touchSlider("Pan", value: floatAsDouble(voice.pan), range: -1...1, width: 110)
                touchSlider("Sweep", value: floatAsDouble(voice.sweep), range: 0...1, width: 110)
                touchSlider("Speed", value: floatAsDouble(voice.sweepRate), range: 0.1...10, width: 110)
            }
        }
    }

    private var spatialControls: some View {
        Group {
            Toggle("Spatializer", isOn: $spatial.isEnabled)
            if let location = selectedSpatialLocation {
                touchSlider("Height", value: spatialElevationBinding(location.id), range: -90...90, width: 180)
            }
            touchSlider("Reverb", value: floatAsDouble($spatial.reverb), range: 0...100, width: 180)
        }
    }

    private var equalizerControls: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                VStack(spacing: 2) {
                    Text(["60", "250", "1k", "4k", "12k"][index])
                        .font(.caption2.monospacedDigit())
                    Slider(value: eqBinding(index), in: -18...18)
                        .frame(width: 105)
                    Text(String(format: "%+.0f dB", lab.eqGains[index]))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
    }

    private var isAnythingPlaying: Bool {
        manager.isPlaying || manager.isMicLive || lab.isPlaying
    }

    private var scopeLabels: [String] { ["Waveform", "3D", "Lissajous"] }

    private var scopeModeBinding: Binding<Double> {
        Binding(get: { Double(scopeMode) }, set: { scopeMode = Int($0.rounded()) })
    }

    private func togglePlayback() {
        if page == 1 {
            lab.togglePlay()
        } else if page == 3 && !manager.isPlaying {
            lab.togglePlay()
        } else if page == 4 && lab.isPlaying {
            lab.togglePlay()
        } else if manager.source == .mic {
            manager.isMicLive ? manager.stopMic() : manager.setSource(.mic)
        } else {
            manager.togglePlayback()
        }
    }

    private func touchSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, width: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2)
            Slider(value: value, in: range)
                .frame(width: width)
        }
    }

    private func floatAsDouble(_ value: Binding<Float>) -> Binding<Double> {
        Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Float($0) })
    }

    private func frequencyBinding(_ value: Binding<Float>) -> Binding<Double> {
        Binding(
            get: { log2(max(20, Double(value.wrappedValue))) },
            set: { value.wrappedValue = Float(pow(2, $0)) }
        )
    }

    private func waveBinding(_ value: Binding<Wave>) -> Binding<Double> {
        Binding(
            get: { Double(value.wrappedValue.rawValue) },
            set: { value.wrappedValue = Wave(rawValue: Int($0.rounded())) ?? .round }
        )
    }

    private func spatialElevationBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { Double(spatial.locations.first(where: { $0.id == id })?.elevation ?? 0) },
            set: { newValue in spatial.updateLocation(id) { $0.elevation = Float(newValue) } }
        )
    }

    private func eqBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { Double(lab.eqGains.indices.contains(index) ? lab.eqGains[index] : 0) },
            set: { newValue in
                guard lab.eqGains.indices.contains(index) else { return }
                var gains = lab.eqGains
                gains[index] = Float(newValue)
                lab.eqGains = gains
            }
        )
    }
}
#endif
