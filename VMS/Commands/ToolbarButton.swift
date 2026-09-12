import SwiftUI
import VMSCore

/// Renders one `EditorCommand` as a compact icon button — used for every toolbar group.
/// Never hand-builds its own action/tooltip/disabled logic; all of that comes from the
/// command definition, so a button here and the matching `.commands` menu item (see
/// `VMSApp`) can never drift apart.
struct ToolbarButton: View {
    @Environment(ProjectStore.self) private var store
    let command: EditorCommand

    var body: some View {
        let context = EditorContext(store: store)
        let enabled = command.isEnabled(context)
        let isOn = command.isOn?(context) ?? false

        Button {
            command.perform(context)
        } label: {
            IconCatalog.resolve(command.iconKey)
                .font(.system(size: 13))
                .frame(width: 24, height: Theme.toolbarHeight - 6)
        }
        .buttonStyle(.plain)
        .background(isOn ? Theme.selectionFill : Color.clear)
        .cornerRadius(Theme.controlCornerRadius)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(command.tooltipWithShortcut)
        .accessibilityLabel(Text(command.title))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
