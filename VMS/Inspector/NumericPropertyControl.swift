import SwiftUI

/// §7-1: label + slider + numeric field (+ optional reset), kept in sync no matter which
/// one the user drags/types/arrow-keys. `value` is `nil` when the selection has mixed
/// values for this property (shown as "—" instead of picking one arbitrarily). Range,
/// step, decimals, and unit are passed in per call site rather than hard-coded per field —
/// the whole point is that a property's *definition* (range/step/unit) lives with the
/// call site that knows what the property means, not scattered across bespoke sliders.
struct NumericPropertyControl: View {
    @Environment(ProjectStore.self) private var store

    let label: String
    let value: Binding<Double?>
    let range: ClosedRange<Double>
    var step: Double = 1
    var decimalPlaces: Int = 0
    var unit: String = ""
    var resetValue: Double?

    @State private var isDraggingSlider = false
    @State private var isEditingField = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(Theme.labelFont)
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .leading)

            Slider(
                value: Binding(
                    get: { value.wrappedValue ?? range.lowerBound },
                    set: { value.wrappedValue = $0 }
                ),
                in: range,
                onEditingChanged: { editing in
                    if editing && !isDraggingSlider {
                        isDraggingSlider = true
                        store.beginUndoableChange()
                    } else if !editing {
                        isDraggingSlider = false
                    }
                }
            )

            TextField(
                "",
                value: Binding(
                    get: { value.wrappedValue ?? range.lowerBound },
                    set: { newValue in
                        if !isEditingField {
                            isEditingField = true
                            store.beginUndoableChange()
                        }
                        value.wrappedValue = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                ),
                format: .number.precision(.fractionLength(decimalPlaces))
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 54)
            .multilineTextAlignment(.trailing)
            .onSubmit { isEditingField = false }
            .onKeyPress(.upArrow) {
                beginFieldEditIfNeeded()
                value.wrappedValue = min(range.upperBound, (value.wrappedValue ?? 0) + step)
                return .handled
            }
            .onKeyPress(.downArrow) {
                beginFieldEditIfNeeded()
                value.wrappedValue = max(range.lowerBound, (value.wrappedValue ?? 0) - step)
                return .handled
            }

            if !unit.isEmpty {
                Text(unit).font(.caption2).foregroundColor(.secondary).frame(width: 20, alignment: .leading)
            }

            if let resetValue {
                Button {
                    store.beginUndoableChange()
                    value.wrappedValue = resetValue
                } label: {
                    IconCatalog.resolve(.reset).font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .help("既定値に戻す")
            }

            if value.wrappedValue == nil {
                Text("混在").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func beginFieldEditIfNeeded() {
        guard !isEditingField else { return }
        isEditingField = true
        store.beginUndoableChange()
    }
}
