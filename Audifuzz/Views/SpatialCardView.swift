import SwiftUI

struct SpatialCardView: View {
    @ObservedObject var stage: SpatialStage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stage.isEnabled ? "dot.radiowaves.left.and.right" : "speaker.slash")
                .foregroundColor(stage.isEnabled ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Spatializer").font(.headline)
                Text(stage.isEnabled ? "Configured in Spatializer" : "Off")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $stage.isEnabled)
                .labelsHidden()
        }
        .card()
    }
}

struct SpatializerView: View {
    @ObservedObject var stage: SpatialStage

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                spatialField
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 54, height: 54)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text("Spatializer").font(.largeTitle.bold())
                Text("Place your sound around the listener with headphone-ready 3D audio.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $stage.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private var spatialField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sound field").font(.headline)
                Spacer()
                Text(stage.isEnabled ? "LIVE" : "BYPASSED")
                    .font(.caption.weight(.bold))
                    .foregroundColor(stage.isEnabled ? .accentColor : .secondary)
            }

            HStack(alignment: .center, spacing: 22) {
                SpatialPadView(azimuth: $stage.azimuth, distance: $stage.distance)
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                    .opacity(stage.isEnabled ? 1 : 0.48)
                    .allowsHitTesting(stage.isEnabled)

                VStack(spacing: 20) {
                    VerticalSpatialSlider(
                        title: "HEIGHT",
                        value: $stage.elevation,
                        range: -90...90,
                        valueText: { "\(Int($0.rounded()))°" }
                    )
                    VerticalSpatialSlider(
                        title: "REVERB",
                        value: $stage.reverb,
                        range: 0...100,
                        valueText: { "\(Int($0.rounded()))%" }
                    )
                }
                .frame(width: 76)
            }

            HStack {
                fieldReadout(title: "DIRECTION", value: directionText)
                Spacer()
                fieldReadout(title: "DISTANCE", value: String(format: "%.1f m", stage.distance))
            }
        }
        .card()
    }

    private var directionText: String {
        let degrees = Int(stage.azimuth.rounded())
        if abs(degrees) < 3 { return "Front" }
        if abs(abs(degrees) - 180) < 3 { return "Behind" }
        return degrees < 0 ? "Left \(-degrees)°" : "Right \(degrees)°"
    }

    private func fieldReadout(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }
}

private struct VerticalSpatialSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let valueText: (Float) -> String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(valueText(value))
                .font(.caption.monospacedDigit())
            Slider(value: $value, in: range)
                .tint(.accentColor)
                .frame(width: 132)
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 132)
        }
    }
}

/// Top-down view: you're in the middle, drag the dot to place the sound.
struct SpatialPadView: View {
    @Binding var azimuth: Float      // degrees, 0 = front, +90 = right
    @Binding var distance: Float     // meters
    var maxDistance: Float = 10

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            spatialField(side: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup()
    }

    private func spatialField(side: CGFloat) -> some View {
        let radius = side / 2
        let az = Double(azimuth) * .pi / 180
        let r = CGFloat(distance / maxDistance) * radius

        return ZStack {
            Circle().fill(Color.accentColor.opacity(0.06))
            Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
            Circle().stroke(Color.secondary.opacity(0.2)).scaleEffect(0.67)
            Circle().stroke(Color.secondary.opacity(0.15)).scaleEffect(0.34)
            Path { path in
                path.move(to: CGPoint(x: radius, y: 0))
                path.addLine(to: CGPoint(x: radius, y: side))
                path.move(to: CGPoint(x: 0, y: radius))
                path.addLine(to: CGPoint(x: side, y: radius))
            }
            .stroke(Color.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
            orientationLabels(side: side, radius: radius)
            Image(systemName: "person.fill")
                .font(.title3)
                .foregroundColor(.primary)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
                .position(x: radius, y: radius)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                .position(x: radius + r * CGFloat(sin(az)), y: radius - r * CGFloat(cos(az)))
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
            let dx = gesture.location.x - radius
            let dy = gesture.location.y - radius
            let dist = min(hypot(dx, dy), radius)
            azimuth = Float(atan2(dx, -dy) * 180 / .pi)
            distance = max(0.5, Float(dist / radius) * maxDistance)
        })
    }

    private func orientationLabels(side: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            Text("FRONT").font(.caption2.weight(.semibold)).foregroundColor(.secondary).position(x: radius, y: 12)
            Text("L").font(.caption2.weight(.semibold)).foregroundColor(.secondary).position(x: 13, y: radius)
            Text("R").font(.caption2.weight(.semibold)).foregroundColor(.secondary).position(x: side - 13, y: radius)
            Text("BACK").font(.caption2.weight(.semibold)).foregroundColor(.secondary).position(x: radius, y: side - 12)
        }
    }
}
