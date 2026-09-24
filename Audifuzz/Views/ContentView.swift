import SwiftUI

struct ContentView: View {
    @StateObject private var manager = AudioEngineManager()
    @StateObject private var lab = SoundLabEngine()
    @State private var selection: Int? = 0

    var body: some View {
        NavigationView {
            List {
                NavigationLink(
                    destination: EditorView(manager: manager),
                    tag: 0,
                    selection: $selection
                ) {
                    Label("Editor", systemImage: "slider.horizontal.3")
                }

                NavigationLink(
                    destination: SoundLabView(lab: lab) { url in
                        manager.load(url: url)
                        selection = 0
                    },
                    tag: 1,
                    selection: $selection
                ) {
                    Label("Sound Lab", systemImage: "waveform")
                }
            }
            .listStyle(.sidebar)
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.leading")
                    }
                }
            }
            #endif

            // Default page shown when the app launches (Mac)
            EditorView(manager: manager)
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }

    #if os(macOS)
    /// Programmatically toggles the macOS sidebar open and closed.
    /// AppKit only: this must stay inside #if os(macOS) or the iPhone build breaks.
    private func toggleSidebar() {
        _ = NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }
    #endif
}
