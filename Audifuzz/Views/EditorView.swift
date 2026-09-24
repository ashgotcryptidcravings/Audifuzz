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
                    Text("Audifuzz Beta")
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
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 12, height: 12)
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
        HStack(spacing: 0) {
            ForEach(AudioEngineManager.Source.allCases) { source in
                Button(source.rawValue) {
                    manager.setSource(source)
                }
                .buttonStyle(.borderedProminent)
                .tint(manager.source == source ? .accentColor : .secondary)
                .opacity(manager.source == source ? 1 : 0.55)
            }
        }
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
