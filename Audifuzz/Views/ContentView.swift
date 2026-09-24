import SwiftUI

struct ContentView: View {
    @StateObject private var manager = AudioEngineManager()
    @StateObject private var lab = SoundLabEngine()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            EditorView(manager: manager)
                .tabItem { Label("Editor", systemImage: "slider.horizontal.3") }
                .tag(0)

            SoundLabView(lab: lab) { url in
                manager.load(url: url)
                tab = 0
            }
            .tabItem { Label("Sound Lab", systemImage: "waveform") }
            .tag(1)
        }
    }
}
