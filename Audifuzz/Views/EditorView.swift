import SwiftUI
import UniformTypeIdentifiers

/// Main tab: load a file (or use the mic) and tweak the effect dials.
struct EditorView: View {
    @ObservedObject var manager: AudioEngineManager
    @State private var showImporter = false

/// Main page title
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text("Audifuzz")
                        .font(.largeTitle.bold())
                    
                    Text("Distort any audio! Use an existing file or live audio from your microphone.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                statusLine
                sourcePicker
                controls
/// Title End

                if let message = manager.errorMessage {
                    Text(message).font(.footnote).foregroundColor(.red)
                }

                ForEach(manager.effects) { fx in
                    EffectCardView(effect: fx) { offset in
                        manager.move(fx, by: offset)
                    }
                }
                SpatialCardView(stage: manager.spatial)
            }
            .padding()
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { manager.load(url: url) }
        }
    }

    private var statusLine: some View {
        Group {
            if manager.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading file…")
                }
            } else if manager.source == .mic {
                Text(manager.isRecording ? "Recording…" : "Mic is live. Use headphones to avoid feedback.")
            } else {
                Text(manager.fileName ?? "No file loaded")
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    private var sourcePicker: some View {
        Picker("Source", selection: Binding(
            get: { manager.source },
            set: { manager.setSource($0) }
        )) {
            ForEach(AudioEngineManager.Source.allCases) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 240)
    }

    /// Button Toolbar
    private var controls: some View {
        HStack {
            if manager.source == .file {
                Button("Open") { showImporter = true }
                Button(manager.isPlaying ? "Stop" : "Play") {
                    manager.isPlaying ? manager.stop() : manager.play()
                }
                .disabled(manager.fileName == nil || manager.isLoading)
            } else {
                Button(manager.isRecording ? "Stop & Use" : "Record Sample") {
                    manager.toggleRecording()
                }
            }
            Button("Randomize") { manager.randomize() }
            Button("Reset") { manager.resetAll() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
