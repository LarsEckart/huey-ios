import HueCore
import SwiftUI

struct GroupToggleRow: View {
    let group: HueGroup
    let isBusy: Bool
    let onChange: @Sendable (Bool) -> Void
    let onBrightnessChange: @Sendable (Int) -> Void

    @State private var brightness: Double
    @State private var isEditingBrightness = false

    init(
        group: HueGroup,
        isBusy: Bool,
        onChange: @escaping @Sendable (Bool) -> Void,
        onBrightnessChange: @escaping @Sendable (Int) -> Void
    ) {
        self.group = group
        self.isBusy = isBusy
        self.onChange = onChange
        self.onBrightnessChange = onBrightnessChange
        _brightness = State(initialValue: Double(group.brightness ?? 254))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { group.anyOn },
                    set: onChange
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                    Text("\(group.type) • id \(group.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)

                Slider(
                    value: $brightness,
                    in: 1...254,
                    step: 1
                ) { isEditing in
                    isEditingBrightness = isEditing
                    if !isEditing {
                        onBrightnessChange(Int(brightness.rounded()))
                    }
                }
                .accessibilityLabel("Brightness")

                Text("\(brightnessPercent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .disabled(isBusy)
        .onChange(of: group.brightness) { _, newBrightness in
            if !isEditingBrightness {
                brightness = Double(newBrightness ?? 254)
            }
        }
    }

    private var brightnessPercent: Int {
        Int((brightness / 254 * 100).rounded())
    }
}
