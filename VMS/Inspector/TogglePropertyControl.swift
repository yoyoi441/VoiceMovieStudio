import SwiftUI

/// §7-2: on/off switch with a clearly distinct visual for each state (native `.switch`
/// style already does this — filled+accent when on, outline when off) plus a "混在" label
/// when the selection disagrees.
struct TogglePropertyControl: View {
    let label: String
    let value: Binding<Bool?>

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.labelFont)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { value.wrappedValue ?? false },
                set: { value.wrappedValue = $0 }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)

            if value.wrappedValue == nil {
                Text("混在").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}
