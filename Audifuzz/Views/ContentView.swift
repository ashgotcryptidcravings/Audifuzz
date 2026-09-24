import SwiftUI

struct ContentView: View {
    @StateObject private var manager = AudioEngineManager()
    @StateObject private var lab = SoundLabEngine()
    @State private var selection: Int? = 0
    @AppStorage("audifuzzWhatsNewVersion") private var whatsNewVersion = ""
    @State private var showWhatsNew = false

    private let currentWhatsNewVersion = "2026.09.24.1"

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

                NavigationLink(
                    destination: SpatializerView(stage: manager.spatial),
                    tag: 2,
                    selection: $selection
                ) {
                    Label("Spatializer", systemImage: "dot.radiowaves.left.and.right")
                }

                NavigationLink(
                    destination: EqualizerView(lab: lab),
                    tag: 3,
                    selection: $selection
                ) {
                    Label("Equalizer", systemImage: "slider.vertical.3")
                }

                NavigationLink(
                    destination: SoundLibraryView(lab: lab) { url in
                        manager.load(url: url)
                        selection = 0
                    },
                    tag: 4,
                    selection: $selection
                ) {
                    Label("Sound Library", systemImage: "books.vertical")
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
        .onAppear {
            if whatsNewVersion != currentWhatsNewVersion {
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: {
            whatsNewVersion = currentWhatsNewVersion
        }) {
            WhatsNewView {
                showWhatsNew = false
            }
        }
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

private struct WhatsNewView: View {
    let onDone: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 70, height: 70)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                
                Text("Here's what's new!")
                    .font(.largeTitle.bold())
                Text("More sounds to shape, explore, and make your own.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            .padding(.horizontal, 28)
            
            ScrollView {
                VStack(spacing: 12) {
                    whatsNewRow(
                        icon: "books.vertical",
                        title: "Sound Library",
                        detail: "Browse included sounds, open their details, and send any of them straight to the Editor."
                    )
                    whatsNewRow(
                        icon: "music.note.list",
                        title: "Bundled audio",
                        detail: "Packaged MP3, WAV, M4A, AIF, and CAF files can now appear in the library automatically."
                    )
                    whatsNewRow(
                        icon: "waveform.badge.plus",
                        title: "Room to grow",
                        detail: "Ten reserved sound slots are ready for future audio additions without changing the library layout."
                    )
                    whatsNewRow(
                        icon: "info.circle",
                        title: "Sound details",
                        detail: "Inspect length, channels, bitrate, key, and date added before using a sound."
                    )
                }
                .padding(28)
            }
            
            Button("Start exploring", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .frame(minWidth: 360, minHeight: 500)
    }
    
    private func whatsNewRow(icon: String, title: String, detail: String) -> some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    } // <-- Closes WhatsNewView

    // Move the preview out here to the global scope:
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
