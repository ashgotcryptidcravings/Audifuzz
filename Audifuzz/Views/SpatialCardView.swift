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
    @Binding var selectedLocationID: UUID?

    private var selectedLocation: SpatialLocation {
        stage.locations.first(where: { $0.id == selectedLocationID }) ?? stage.locations[0]
    }

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
                Text("Place sources in 3D using Apple’s device-aware spatial audio renderer.")
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

                    HStack(spacing: 8) {
                        ForEach(Array(stage.locations.enumerated()), id: \.element.id) { index, location in
                            Button("Source \(index + 1)") { selectedLocationID = location.id }
                                .buttonStyle(.bordered)
                                .tint(selectedLocation.id == location.id ? .accentColor : .secondary)
                                .controlSize(.small)
                        }
                        Button { stage.addLocation(); selectedLocationID = stage.locations.last?.id } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(stage.locations.count >= stage.sourceMixers.count)
                        Button { stage.removeLocation(selectedLocation.id) } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(stage.locations.count <= 1)
                    }

                    HStack(alignment: .center, spacing: 22) {
                SpatialPadView(
                    azimuth: locationBinding(\.azimuth),
                    distance: locationBinding(\.distance),
                    otherLocations: stage.locations.filter { $0.id != selectedLocation.id }
                )
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                    .opacity(stage.isEnabled ? 1 : 0.48)
                    .allowsHitTesting(stage.isEnabled)

                VStack(spacing: 20) {
                    SnappingVerticalSlider(
                        title: "HEIGHT",
                        value: locationBinding(\.elevation),
                        range: -90...90,
                        valueText: { "\(Int($0.rounded()))°" }
                    )
                    SnappingVerticalSlider(
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
                fieldReadout(title: "DISTANCE", value: String(format: "%.1f m", selectedLocation.distance))
            }
        }
        .card()
    }

    private func locationBinding(_ keyPath: WritableKeyPath<SpatialLocation, Float>) -> Binding<Float> {
        let id = selectedLocation.id
        return Binding(
            get: { stage.locations.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
            set: { newValue in stage.updateLocation(id) { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var directionText: String {
        let degrees = Int(selectedLocation.azimuth.rounded())
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

private struct SnappingVerticalSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let valueText: (Float) -> String

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(valueText(value))
                .font(.caption.monospacedDigit())
            SpatialSliderTrack(title: title, value: $value, range: range)
        }
    }
}

private struct SpatialSliderTrack: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>

    private let trackTop: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            let trackHeight = max(1, geometry.size.height - trackTop * 2)
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = trackTop + (1 - fraction) * trackHeight
            let centered = range.lowerBound < 0 && range.upperBound > 0
            let neutralFraction = centered ? CGFloat(-range.lowerBound / (range.upperBound - range.lowerBound)) : 0
            let neutralY = trackTop + (1 - neutralFraction) * trackHeight
            let fillTop = centered ? min(thumbY, neutralY) : thumbY
            let fillHeight = centered ? abs(thumbY - neutralY) : geometry.size.height - trackTop - thumbY

            ZStack {
                Capsule().fill(Color.secondary.opacity(0.24))
                    .frame(width: 4, height: trackHeight)
                    .position(x: 12, y: trackTop + trackHeight / 2)
                tickMarks(trackHeight: trackHeight)
                Capsule().fill(Color.accentColor)
                    .frame(width: 4, height: max(0, fillHeight))
                    .position(x: 12, y: fillTop + max(0, fillHeight) / 2)
                Circle().fill(Color.accentColor).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .position(x: 12, y: thumbY)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                updateValue(at: gesture.location.y, trackHeight: trackHeight)
            })
        }
        .frame(width: 54, height: 132)
        .drawingGroup()
    }

    @ViewBuilder
    private func tickMarks(trackHeight: CGFloat) -> some View {
        let marks: [(CGFloat, String)] = title == "HEIGHT"
            ? [(0, "−90°"), (0.5, "0°"), (1, "+90°")]
            : [(0, "0%"), (0.5, "50%"), (1, "100%")]
        ForEach(Array(marks.enumerated()), id: \.offset) { _, item in
            let y = trackTop + (1 - item.0) * trackHeight
            Rectangle().fill(Color.secondary)
                .frame(width: 8, height: 1)
                .position(x: 12, y: y)
            Text(item.1)
                .font(.system(size: 8, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 34, alignment: .leading)
                .position(x: 37, y: y)
        }
    }

    private func updateValue(at y: CGFloat, trackHeight: CGFloat) {
        let normalized = min(1, max(0, 1 - (y - trackTop) / trackHeight))
        let marks: [CGFloat] = [0, 0.5, 1]
        let snapped = marks.first(where: { abs(normalized - $0) < 0.035 }) ?? normalized
        value = range.lowerBound + Float(snapped) * (range.upperBound - range.lowerBound)
    }
}

/// Top-down view: you're in the middle, drag the dot to place the sound.
struct SpatialPadView: View {
    @Binding var azimuth: Float      // degrees, 0 = front, +90 = right
    @Binding var distance: Float     // meters
    var otherLocations: [SpatialLocation] = []
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
            ForEach(Array(otherLocations.enumerated()), id: \.element.id) { index, location in
                let sourceAzimuth = Double(location.azimuth) * .pi / 180
                let sourceRadius = CGFloat(location.distance / maxDistance) * radius
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color.cyan : Color.purple)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                    .position(x: radius + sourceRadius * CGFloat(sin(sourceAzimuth)),
                              y: radius - sourceRadius * CGFloat(cos(sourceAzimuth)))
            }
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
