import SwiftUI
import Combine

struct OscilloscopeView: View {
    @ObservedObject var manager: AudioEngineManager
    @ObservedObject var lab: SoundLabEngine
    @Binding var shapeMode: Int
    @StateObject private var threeDimensionalScene = Oscilloscope3DScene()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 54, height: 54)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Oscilloscope").font(.largeTitle.bold())
                        Text("Watch the processed Editor output in real time.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("Display", selection: $shapeMode) {
                            Text("Waveform").tag(0)
                            Text("3D Phase").tag(1)
                            Text("Lissajous").tag(2)
                        }
                        .pickerStyle(.segmented)
                        Spacer()
                        Text((lab.isPlaying || lab.isMIDIActive) ? "SYNTHSPACE / MIDI" : manager.source.rawValue.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundColor(.accentColor)
                    }
                    Group {
                        if shapeMode == 1 {
                            OscilloscopeSceneHost(scene: threeDimensionalScene.scene)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .accessibilityLabel("Interactive three-dimensional stereo oscilloscope")
                        } else {
                            TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !manager.isPlaying && !manager.isMicLive && !lab.isPlaying)) { _ in
                                let stereoSamples = activeScopeSnapshot
                                OscilloscopeGraph(left: stereoSamples.left, right: stereoSamples.right, mode: shapeMode)
                                    .frame(height: 280)
                                    .accessibilityLabel("Live audio waveform")
                            }
                        }
                    }
                    Text(lab.isPlaying || lab.isMIDIActive
                         ? "Showing live SynthSpace output. Drag the 3D view to rotate it."
                         : manager.isPlaying || manager.isMicLive
                            ? "Showing the signal after Editor effects and spatial processing. Drag the 3D view to rotate it."
                            : "Start playback, play SynthSpace, or turn on the Editor mic to view a signal.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .card()
            }
            .padding()
        }
        .onReceive(Timer.publish(every: 1.0 / 120.0, on: .main, in: .common).autoconnect()) { _ in
            let stereoSamples = activeScopeSnapshot
            threeDimensionalScene.update(left: stereoSamples.left, right: stereoSamples.right)
        }
    }

    private var activeScopeSnapshot: (left: [Float], right: [Float]) {
        if lab.isPlaying || lab.isMIDIActive {
            return (lab.waveform, lab.waveformRight)
        }
        return manager.oscilloscopeStereoSnapshot()
    }
}

private struct OscilloscopeGraph: View {
    let left: [Float]
    let right: [Float]
    let mode: Int

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.88))
                Path { path in
                    for column in 0...8 {
                        let x = size.width * CGFloat(column) / 8
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for row in 0...4 {
                        let y = size.height * CGFloat(row) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.13), lineWidth: 1)

                Path { path in
                    guard left.count > 1, right.count == left.count else { return }
                    let strideSize = mode == 0 ? 4 : 2
                    for index in Swift.stride(from: 0, to: left.count, by: strideSize) {
                        let t = CGFloat(index) / CGFloat(left.count - 1)
                        let l = CGFloat(max(-1, min(1, left[index])))
                        let r = CGFloat(max(-1, min(1, right[index])))
                        let point: CGPoint
                        if mode == 0 {
                            point = CGPoint(x: size.width * t, y: size.height * (0.5 - l * 0.44))
                        } else {
                            point = CGPoint(x: size.width * (0.5 + l * 0.42),
                                            y: size.height * (0.5 - r * 0.42))
                        }
                        if index == 0 { path.move(to: point) }
                        else { path.addLine(to: point) }
                    }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: mode == 0 ? 2 : 1.7, lineCap: .round, lineJoin: .round))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .drawingGroup()
    }
}
