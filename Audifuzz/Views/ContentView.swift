import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var manager: AudioEngineManager
    @State private var showImporter = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Audifuzz")
                .font(.largeTitle.bold())

            Text(manager.fileName ?? "No file loaded")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack {
                Button("Open") { showImporter = true }
                Button(manager.isPlaying ? "Stop" : "Play") {
                    manager.isPlaying ? manager.stop() : manager.play()
                }
                .disabled(manager.fileName == nil)
                Button("Randomize") { manager.randomize() }
                Button("Reset") { manager.resetAll() }
            }
            .buttonStyle(.bordered)

            if let message = manager.errorMessage {
                Text(message).font(.footnote).foregroundColor(.red)
            }

            List {
                ForEach(manager.effects) { fx in
                    EffectRowView(effect: fx) { offset in
                        manager.move(fx, by: offset)
                    }
                }
            }
        }
        .padding()
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { manager.load(url: url) }
        }
    }
}
