import SwiftUI

struct EffectRowView: View {
    @ObservedObject var effect: EffectModule
    var onMove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(effect.name, isOn: $effect.isEnabled)
                    .font(.headline)
                Spacer()
                Button { onMove(-1) } label: { Image(systemName: "chevron.up") }
                Button { onMove(1) } label: { Image(systemName: "chevron.down") }
            }
            .buttonStyle(.borderless)

            if effect.isEnabled {
                ForEach($effect.parameters) { $param in
                    HStack {
                        Text(param.name)
                            .font(.subheadline)
                            .frame(width: 80, alignment: .leading)
                        Slider(value: $param.value, in: param.range)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
