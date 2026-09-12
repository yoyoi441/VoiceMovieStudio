import SwiftUI

/// §7-2: a labeled dropdown for enum-like properties (blend mode, wrap mode, text
/// alignment, …). `options` pairs each value with its display name so callers don't need
/// their model types to be `CustomStringConvertible`.
struct SelectPropertyControl<Option: Hashable>: View {
    let label: String
    let value: Binding<Option?>
    let options: [(Option, String)]

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.labelFont)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            Picker("", selection: Binding<Option?>(
                get: { value.wrappedValue },
                set: { value.wrappedValue = $0 }
            )) {
                if value.wrappedValue == nil {
                    Text("混在").tag(Option?.none)
                }
                ForEach(options, id: \.0) { option, title in
                    Text(title).tag(Option?.some(option))
                }
            }
            .labelsHidden()
        }
    }
}
