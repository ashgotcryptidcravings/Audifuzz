import Foundation
import SwiftUI

struct SoundLibraryView: View {
    @ObservedObject var lab: SoundLabEngine
    var onUseSample: (URL) -> Void

    var body: some View {
        // Keep one stable snapshot for this render. `entries` performs filesystem
        // and bundle lookups, so evaluating it repeatedly can also make SwiftUI
        // replace rows while macOS is resolving a click.
        let entries = BuiltInSoundLibrary.entries

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sound Library")
                        .font(.largeTitle.bold())
                    Text("Original sounds included with Audifuzz.")
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        // Do not apply `.buttonStyle(.plain)` to a NavigationLink
                        // on macOS. In a NavigationView sidebar/detail hierarchy
                        // that style can remove the link's native hit target,
                        // leaving rows visible but apparently unselectable.
                        NavigationLink {
                            SoundDetailView(entry: entry, lab: lab, onUseSample: onUseSample)
                        } label: {
                            SoundLibraryRow(entry: entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if entry.id != entries.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .card()
            }
            .padding()
        }
        .onAppear { lab.refreshSamples() }
    }
}

private struct SoundLibraryRow: View {
    let entry: BuiltInSoundLibrary.Entry

    var body: some View {
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

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct SoundDetailView: View {
    let entry: BuiltInSoundLibrary.Entry
    @ObservedObject var lab: SoundLabEngine
    var onUseSample: (URL) -> Void

    private var details: BuiltInSoundLibrary.Details? {
        BuiltInSoundLibrary.details(for: entry)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                        Label("Use in Editor", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Sound Details")
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
