import AVFoundation
import Foundation
import SwiftUI

/// The Sound Library page.
///
/// Uses local state for the detail screen so library rows stay independently
/// clickable while the app's toolbar selection remains on Sound Library.
struct SoundLibraryView: View {
    @ObservedObject var lab: SoundLabEngine
    var onUseSample: (URL) -> Void
    var onBack: () -> Void
    @Binding var selectedURL: URL?

    // `entries` does filesystem and bundle lookups, so it is loaded once on
    // appear instead of on every render.
    @State private var entries: [BuiltInSoundLibrary.Entry] = []
    @State private var selected: BuiltInSoundLibrary.Entry?
    @StateObject private var previewPlayer = LibraryPreviewPlayer()

    var body: some View {
        Group {
            if let entry = selected {
                SoundDetailView(entry: entry, lab: lab, onUseSample: onUseSample) {
                    selected = nil
                }
            } else {
                listPage
            }
        }
        .onAppear {
            lab.refreshSamples() // installs the starter WAVs if they're missing
            entries = BuiltInSoundLibrary.entries.filter { !$0.isPlaceholder }
        }
        // Don't let a snippet keep playing after the user leaves the page,
        // or after they've opened a sound's details.
        .onDisappear {
            previewPlayer.stop()
            selectedURL = nil
        }
        .onChange(of: selected?.id) { _ in previewPlayer.stop() }
    }

    private var listPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: onBack) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    Text("Sound Library")
                        .font(.largeTitle.bold())
                    Text("Original sounds included with Audifuzz.")
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        SoundLibraryRow(
                            entry: entry,
                            isPlayingPreview: previewPlayer.playingID == entry.id,
                            onSelect: {
                                selected = entry
                                selectedURL = entry.isPlaceholder ? nil : entry.url
                            },
                            onTogglePreview: { previewPlayer.toggle(entry) }
                        )

                        if entry.id != entries.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .card()
            }
            .padding()
        }
    }
}

/// Plays a short snippet of a library sound so the user can tell what it is
/// without leaving the list. This is a plain `AVAudioPlayer`, not an
/// `AVAudioEngine` node, so it stays independent of the Editor's and Sound
/// Lab's engines per the "never touch another page's engine" rule.
private final class LibraryPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingID: String?

    private var player: AVAudioPlayer?
    private let snippetDuration: TimeInterval = 5

    func toggle(_ entry: BuiltInSoundLibrary.Entry) {
        guard let url = entry.url, !entry.isPlaceholder else { return }

        if playingID == entry.id {
            stop()
            return
        }

        stop()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            playingID = entry.id
            scheduleAutoStop(after: min(snippetDuration, newPlayer.duration))
        } catch {
            print("[SoundLibraryView] FAILURE: Could not preview \(entry.name): \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    private func scheduleAutoStop(after seconds: TimeInterval) {
        guard seconds > 0 else { return }
        let token = player
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            // Only stop if this is still the same playback (nothing newer started).
            guard let self, self.player === token else { return }
            self.stop()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player === player else { return }
            self.stop()
        }
    }
}

private struct SoundLibraryRow: View {
    let entry: BuiltInSoundLibrary.Entry
    let isPlayingPreview: Bool
    let onSelect: () -> Void
    let onTogglePreview: () -> Void

    private var isPlayable: Bool {
        entry.url != nil && !entry.isPlaceholder
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onSelect) {
                HStack(spacing: 14) {
                    Image(systemName: entry.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 42, height: 42)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name.replacingOccurrences(of: ".wav", with: ""))
                            .font(.headline)
                        Text(entry.isPlaceholder ? "Coming soon" : (entry.key.map { "Key \($0)" } ?? "No fixed key"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPlayable {
                Button(action: onTogglePreview) {
                    Image(systemName: isPlayingPreview ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help(isPlayingPreview ? "Stop preview" : "Play a short preview")
            }
        }
        .padding(.vertical, 10)
    }
}

private struct SoundDetailView: View {
    let entry: BuiltInSoundLibrary.Entry
    @ObservedObject var lab: SoundLabEngine
    var onUseSample: (URL) -> Void
    var onBack: () -> Void

    private var details: BuiltInSoundLibrary.Details? {
        BuiltInSoundLibrary.details(for: entry)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .accessibilityLabel("Back to Sound Library")
                    Spacer()
                }

                Image(systemName: entry.symbol)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 88, height: 88)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text(entry.name.replacingOccurrences(of: ".wav", with: ""))
                    .font(.title.bold())

                if entry.isPlaceholder {
                    Text("This library slot is reserved for a future bundled sound.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .card()
                } else if let details = details {
                    VStack(spacing: 0) {
                        metadataRow("File length", value: formatDuration(details.duration))
                        metadataRow("Channels", value: details.channels == 1 ? "Mono" : "\(details.channels)-channel")
                        metadataRow("Bitrate", value: "\(details.bitrate / 1000) kbps")
                        metadataRow("Key", value: details.key ?? "Not specified")
                        metadataRow("Date added", value: details.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    }
                    .card()
                }

                if let url = entry.url {
                    Button {
                        lab.stopPreview()
                        onUseSample(url)
                    } label: {
                        Label("Add to Editor", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .padding(.vertical, 8)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.2f seconds", duration)
    }
}
