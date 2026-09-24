import SwiftUI

struct SpatialCardView: View {
    @ObservedObject var stage: SpatialStage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Spatializer (best with headphones)", isOn: $stage.isEnabled)
                .font(.headline)

            if stage.isEnabled {
                SpatialPadView(azimuth: $stage.azimuth, distance: $stage.distance)
                    .frame(maxWidth: 220)
                    .frame(maxWidth: .infinity)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    Dial(title: "Direction", value: $stage.azimuth, range: -180...180, unit: "°")
                    Dial(title: "Height", value: $stage.elevation, range: -90...90, unit: "°")
                    Dial(title: "Distance", value: $stage.distance, range: 0.5...10, unit: " m")
                    Dial(title: "Reverb", value: $stage.reverb, range: 0...100, unit: "%")
                }

                Text("Drag the dot. Top is in front of you, the sides are your left and right ear.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .card()
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
            let radius = side / 2
            let az = Double(azimuth) * .pi / 180
            let r = CGFloat(distance / maxDistance) * radius

            ZStack {
                Circle().stroke(Color.secondary.opacity(0.4))
                Circle().stroke(Color.secondary.opacity(0.2)).scaleEffect(0.5)
                Text("front").font(.caption2).foregroundColor(.secondary).position(x: radius, y: 10)
                Text("L").font(.caption2).foregroundColor(.secondary).position(x: 10, y: radius)
                Text("R").font(.caption2).foregroundColor(.secondary).position(x: side - 10, y: radius)
                Image(systemName: "person.fill").foregroundColor(.secondary).position(x: radius, y: radius)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .position(x: radius + r * CGFloat(sin(az)), y: radius - r * CGFloat(cos(az)))
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let dx = g.location.x - radius
                    let dy = g.location.y - radius
                    let dist = min(hypot(dx, dy), radius)
                    azimuth = Float(atan2(dx, -dy) * 180 / .pi)
                    distance = max(0.5, Float(dist / radius) * maxDistance)
                }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
