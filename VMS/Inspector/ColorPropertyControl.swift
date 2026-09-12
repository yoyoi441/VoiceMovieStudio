import SwiftUI
import VMSCore

/// §7-3 "現在色が分かる横長のプレビュー": a wide swatch showing the current color plus
/// the system `ColorPicker` to change it. `nil` (mixed selection) shows a dashed outline
/// instead of guessing a color.
struct ColorPropertyControl: View {
    let label: String
    let value: Binding<CodableColor?>

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.labelFont)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            ColorPicker(
                "",
                selection: Binding(
                    get: { value.wrappedValue?.color ?? .white },
                    set: { value.wrappedValue = CodableColor($0) }
                ),
                supportsOpacity: true
            )
            .labelsHidden()
            .fixedSize()

            RoundedRectangle(cornerRadius: 3)
                .fill(value.wrappedValue?.color ?? Color.clear)
                .frame(height: 16)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.border, style: value.wrappedValue == nil ? StrokeStyle(lineWidth: 1, dash: [3, 2]) : StrokeStyle(lineWidth: 1))
                )
        }
    }
}
