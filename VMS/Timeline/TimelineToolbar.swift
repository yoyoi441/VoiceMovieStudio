import SwiftUI
import VMSCore

/// §3: the timeline's own toolbar — zoom, add-item, history/clipboard/edit, and view/
/// project toggles, each group built straight from `CommandRegistry` (see §10 of the
/// spec: "ツールバー項目は...定義データから生成できるようにしてください"). Wrapped in
/// a horizontal `ScrollView` so a narrow window scrolls instead of clipping buttons.
struct TimelineToolbar: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.toolbarGroupSpacing) {
                TimelineZoomControl()
                divider
                group(.itemInsert)
                divider
                group(.history)
                group(.clipboard)
                group(.timelineEdit)
                divider
                group(.view)
                divider
                group(.project)
                group(.fileOps)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: Theme.toolbarHeight)
        .background(Theme.panelBackground)
        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)
    }

    private var divider: some View {
        Divider().frame(height: Theme.toolbarHeight * 0.6)
    }

    private func group(_ kind: CommandGroupKind) -> some View {
        let context = EditorContext(store: store)
        let commands = CommandRegistry.commands(in: kind).filter { $0.isAvailable(context) }
        return HStack(spacing: Theme.toolbarSpacing) {
            ForEach(commands) { command in
                ToolbarButton(command: command)
            }
        }
    }
}
