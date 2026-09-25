import SwiftUI

struct ContentView: View {
    @StateObject private var manager = AudioEngineManager()
    @StateObject private var lab = SoundLabEngine()
    @StateObject private var midi = MIDIInputManager.shared
    @State private var selection = 0
    @State private var selectedVoiceIndex = 0
    @State private var scopeMode = 0
    @State private var selectedSpatialLocationID: UUID?
    @State private var selectedLibraryURL: URL?
    @AppStorage("audifuzzWhatsNewVersion") private var whatsNewVersion = ""
    @State private var showWhatsNew = false

    private let currentWhatsNewVersion = "2026.09.24.4"
    private let destinations: [(title: String, symbol: String)] = [
        ("Editor", "slider.horizontal.3"),
        ("SynthSpace", "waveform"),
        ("Spatializer", "dot.radiowaves.left.and.right"),
        ("Equalizer", "slider.vertical.3"),
        ("Oscilloscope", "waveform.path")
    ]

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingBar(manager: manager)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            Group {
                switch selection {
                case 1:
                    SoundLabView(lab: lab, selectedVoiceIndex: $selectedVoiceIndex) { url in
                        manager.load(url: url)
                        selection = 0
                    }
                case 2:
                    SpatializerView(stage: manager.spatial, selectedLocationID: $selectedSpatialLocationID)
                case 3:
                    EqualizerView(lab: lab)
                case 4:
                    OscilloscopeView(manager: manager, lab: lab, shapeMode: $scopeMode)
                case 5:
                    SoundLibraryView(lab: lab, onUseSample: { url in
                        manager.load(url: url)
                        selectedLibraryURL = nil
                        selection = 0
                    }, onBack: { selectedLibraryURL = nil }, selectedURL: $selectedLibraryURL)
                case 6:
                    PreferencesView(midi: midi)
                default:
                    EditorView(manager: manager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 500)
#if os(macOS)
        .touchBar {
            TouchBarControls(
                manager: manager,
                lab: lab,
                spatial: manager.spatial,
                page: $selection,
                selectedVoiceIndex: $selectedVoiceIndex,
                scopeMode: $scopeMode,
                selectedSpatialLocationID: $selectedSpatialLocationID,
                selectedLibraryURL: $selectedLibraryURL,
                addSelectedSample: addSelectedLibrarySample
            )
        }
#endif
        .toolbar {
#if os(macOS)
            ToolbarItemGroup(placement: .navigation) { navigationButtons }
#else
            ToolbarItemGroup(placement: .navigationBarTrailing) { navigationButtons }
#endif
        }
        .onAppear {
            if whatsNewVersion != currentWhatsNewVersion { showWhatsNew = true }
        }
        .onReceive(midi.messages) { message in
            switch message {
            case let .noteOn(channel, note, velocity):
                lab.receiveMIDINoteOn(channel: channel, note: note, velocity: velocity,
                                      mode: midi.mode, selectedInstrument: midi.selectedInstrument,
                                      velocityEnabled: midi.velocityControlsVolume)
            case let .noteOff(channel, note):
                lab.receiveMIDINoteOff(channel: channel, note: note)
            case let .pitchBend(_, value):
                lab.receiveMIDIPitchBend(value: value, rangeInSemitones: midi.pitchBendRange)
            case let .channelPressure(channel, value):
                lab.receiveMIDIChannelPressure(channel: channel, value: value)
            case let .polyPressure(channel, note, value):
                lab.receiveMIDIPolyPressure(channel: channel, note: note, value: value)
            case let .controlChange(_, controller, value):
                if controller == 1 { lab.receiveMIDIModulation(value: value) }
                if midi.effectsCCEnabled, let index = midi.knobIndex(for: controller) {
                    manager.receiveMIDIControlChange(parameterIndex: index, value: value)
                }
            case let .effectButton(index, enabled):
                if midi.effectsCCEnabled { manager.receiveMIDIEffectButton(index: index, enabled: enabled) }
            case .allNotesOff:
                lab.receiveMIDIAllNotesOff()
            }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: {
            whatsNewVersion = currentWhatsNewVersion
        }) {
            WhatsNewView { showWhatsNew = false }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 4) {
            ForEach(Array(destinations.enumerated()), id: \.offset) { index, destination in
                navigationButton(index: index, title: destination.title, symbol: destination.symbol)
            }
#if os(iOS)
            navigationButton(index: 6, title: "Settings", symbol: "gearshape")
#endif
            navigationButton(index: 5, title: "Sound Library", symbol: "books.vertical")
        }
    }

    private func addSelectedLibrarySample() {
        guard let url = selectedLibraryURL else { return }
        lab.stopPreview()
        manager.load(url: url)
        selectedLibraryURL = nil
        selection = 0
    }

    private func navigationButton(index: Int, title: String, symbol: String) -> some View {
        Button {
            selection = index
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 30)
                .foregroundColor(selection == index ? .white : .primary)
                .background(selection == index ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct NowPlayingBar: View {
    @ObservedObject var manager: AudioEngineManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: manager.source == .mic ? "mic.fill" : "waveform")
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.isLoading ? "Loading…" : (manager.fileName ?? "Nothing Playing"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(manager.source == .mic && manager.isMicLive ? "Microphone" : (manager.isPlaying ? "Playing" : "Paused"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 100, maxWidth: 220, alignment: .leading)

            Button {
                manager.togglePlayback()
            } label: {
                Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(manager.fileName == nil || manager.isLoading || manager.isMicLive)
            .help(manager.isPlaying ? "Pause" : "Play")

            Button {
                manager.isLooping.toggle()
            } label: {
                Image(systemName: "repeat")
                    .foregroundColor(manager.isLooping ? .accentColor : .secondary)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help(manager.isLooping ? "Loop on" : "Loop off")

            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundColor(.secondary)
            Slider(value: $manager.outputVolume, in: 0...1)
                .frame(maxWidth: 130)
                .help("Output volume")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
