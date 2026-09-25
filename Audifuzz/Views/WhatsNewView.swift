import SwiftUI

struct WhatsNewView: View {
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
                Text("A faster, clearer way to shape and explore sound.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 30)
            .padding(.horizontal, 28)

            ScrollView {
                VStack(spacing: 12) {
                    highlight(
                        icon: "pianokeys",
                        title: "App-Wide MIDI Input",
                        detail: "Connect a MIDI keyboard, choose its source and channel, play SynthSpace voices, shape pitch and sustain, and map controller knobs to Editor effects."
                    )
                    highlight(
                        icon: "waveform.path",
                        title: "Live Oscilloscope",
                        detail: "Watch the Editor's processed output with a smooth, display-synchronized waveform."
                    )
                    highlight(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Native Spatial Audio",
                        detail: "Place up to four virtual sound sources in Apple's device-aware 3D renderer. Height and reverb controls snap to marked values."
                    )
                    highlight(
                        icon: "speedometer",
                        title: "Performance Controls",
                        detail: "Use Safe Mode to increase processing buffers, and choose resampling quality for mismatched audio files."
                    )
                    highlight(
                        icon: "slider.vertical.3",
                        title: "Smoother Equalizer",
                        detail: "The live EQ and waveform update in step with your display refresh rate."
                    )
                    highlight(
                        icon: "books.vertical",
                        title: "Sound Library Details",
                        detail: "Click an item's row to open its details; use the separate play button to preview it."
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

    private func highlight(icon: String, title: String, detail: String) -> some View {
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
}
