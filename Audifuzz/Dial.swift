import SwiftUI

/// A rotary knob. Drag up/right to turn up, down/left to turn down.
struct Dial: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var unit: String = ""
    var isLog: Bool = false            // true = better for frequencies
    var size: CGFloat = 56
    var format: ((Float) -> String)? = nil

    @State private var dragStartFraction: Double?

    private var fraction: Double { toFraction(value) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.15))
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(3)
                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(3)
                ZStack {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 3, height: size * 0.22)
                        .offset(y: -size * 0.24)
                }
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-135 + 270 * fraction))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(drag)

            Text(title).font(.caption).lineLimit(1)
            Text(readout)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: size + 16)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragStartFraction == nil { dragStartFraction = fraction }
                let delta = Double(g.translation.width - g.translation.height) / 160
                let f = min(max((dragStartFraction ?? fraction) + delta, 0), 1)
                value = fromFraction(f)
            }
            .onEnded { _ in dragStartFraction = nil }
    }

    private var readout: String {
        if let format = format { return format(value) }
        let span = range.upperBound - range.lowerBound
        let number: String
        if span >= 100 {
            number = String(format: "%.0f", value)
        } else if span >= 10 {
            number = String(format: "%.1f", value)
        } else {
            number = String(format: "%.2f", value)
        }
        return number + unit
    }

    private func toFraction(_ v: Float) -> Double {
        let lo = Double(range.lowerBound)
        let hi = Double(range.upperBound)
        let x = min(max(Double(v), lo), hi)
        if isLog && lo > 0 { return log(x / lo) / log(hi / lo) }
        return (x - lo) / (hi - lo)
    }

    private func fromFraction(_ f: Double) -> Float {
        let lo = Double(range.lowerBound)
        let hi = Double(range.upperBound)
        if isLog && lo > 0 { return Float(lo * pow(hi / lo, f)) }
        return Float(lo + f * (hi - lo))
    }
}

extension View {
    /// Rounded panel used for every section.
    func card() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.1)))
    }
}
