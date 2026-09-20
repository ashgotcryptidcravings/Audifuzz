import SwiftUI

struct EffectCardView: View {
    @ObservedObject var effect: EffectModule
    var onMove: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(effect.name, isOn: $effect.isEnabled)
                    .font(.headline)
                Spacer()
                Button { onMove(-1) } label: { Image(systemName: "chevron.up") }
                Button { onMove(1) } label: { Image(systemName: "chevron.down") }
            }
            .buttonStyle(.borderless)

            if effect.isEnabled {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    ForEach($effect.parameters) { $param in
                        Dial(title: param.name, value: $param.value, range: param.range,
                             unit: param.unit, format: param.display)
                    }
                }
            }
        }
        .card()
    }
}
