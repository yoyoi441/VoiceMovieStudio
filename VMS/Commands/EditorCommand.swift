import SwiftUI
import VMSCore

/// Everything a command's `isAvailable`/`isEnabled`/`isOn`/`perform` closures need. Thin
/// on purpose — right now that's just the store, but keeping it as its own type means
/// adding something later (e.g. clipboard-service, playback controller) doesn't change
/// every command's signature.
@MainActor
struct EditorContext {
    let store: ProjectStore
}

/// One command definition, shared by the toolbar button that triggers it, the `.commands`
/// menu item for the same action, and (later) any context menu — see `CommandRegistry`.
/// Commands for features that don't exist yet are still registered (per spec §3-2/§3-4:
/// "ボタン定義とコマンド定義を分離し、後から機能を追加できるようにする") — their
/// `isEnabled` returns `false` and/or `perform` surfaces "未実装" via `store.errorMessage`.
@MainActor
struct EditorCommand: Identifiable {
    let id: CommandID
    let group: CommandGroupKind
    let title: String
    let tooltip: String
    let iconKey: IconKey
    let shortcut: KeyboardShortcutSpec?
    var isAvailable: (EditorContext) -> Bool = { _ in true }
    var isEnabled: (EditorContext) -> Bool = { _ in true }
    /// Non-nil marks this as a toggle command; the returned value is its on/off state.
    var isOn: ((EditorContext) -> Bool)?
    let perform: (EditorContext) -> Void

    /// Tooltip with the shortcut appended, e.g. "コピー (⌘C)" — matches the format used
    /// throughout §4 of the spec.
    var tooltipWithShortcut: String {
        guard let shortcut else { return tooltip }
        return "\(tooltip) (\(shortcut.displayString))"
    }
}

/// Marks a command as not yet implemented: disabled, and if ever invoked directly (e.g. a
/// stray shortcut), surfaces a clear "not implemented" message instead of silently doing
/// nothing or crashing.
@MainActor
func unimplementedCommand(
    id: CommandID,
    group: CommandGroupKind,
    title: String,
    tooltip: String,
    iconKey: IconKey,
    shortcut: KeyboardShortcutSpec? = nil
) -> EditorCommand {
    EditorCommand(
        id: id,
        group: group,
        title: title,
        tooltip: "\(tooltip)(未実装)",
        iconKey: iconKey,
        shortcut: shortcut,
        isEnabled: { _ in false },
        perform: { context in
            context.store.errorMessage = "「\(title)」は未実装です。"
        }
    )
}
