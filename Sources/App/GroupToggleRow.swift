import SwiftUI

struct GroupToggleRow: View {
    let group: HueGroup
    let isBusy: Bool
    let onChange: @Sendable (Bool) -> Void

    var body: some View {
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
        .disabled(isBusy)
    }
}
