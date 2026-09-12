import AppKit
import Foundation
import VMSCore

/// The single source of truth for every command in the editor. `TimelineToolbar` builds
/// its buttons from this list grouped by `group`; `VMSApp`'s `.commands` builds
/// menu items from the same list — neither hand-writes its own action closures.
@MainActor
enum CommandRegistry {
    static let all: [EditorCommand] = fileCommands + historyCommands + clipboardEditCommands + playbackCommands + timelineHelperCommands + addItemCommands

    private static var byID: [CommandID: EditorCommand] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func command(_ id: CommandID) -> EditorCommand {
        // Force-unwrap is safe: `byID` is derived from `all`, which is exhaustive over
        // every `CommandID` case (enforced by the `CommandID.allCases` coverage check in
        // `CommandRegistryTests`-equivalent... actually enforced by `assertAllCommandsRegistered()` below, called once at app launch).
        byID[id]!
    }

    static func commands(in group: CommandGroupKind) -> [EditorCommand] {
        all.filter { $0.group == group }
    }

    /// Fails loudly in debug builds if a `CommandID` case was added without a matching
    /// `EditorCommand` — cheaper than discovering it as a missing/crashing toolbar button.
    static func assertAllCommandsRegistered() {
        let missing = Set(CommandID.allCases).subtracting(byID.keys)
        assert(missing.isEmpty, "Missing EditorCommand registrations for: \(missing)")
    }

    // MARK: - File / project

    private static let fileCommands: [EditorCommand] = [
        EditorCommand(
            id: .newProject, group: .fileOps, title: "新規プロジェクト", tooltip: "新規プロジェクト",
            iconKey: .newProject, shortcut: KeyboardShortcutSpec("n"),
            perform: { context in context.store.resetToNewProject() }
        ),
        EditorCommand(
            id: .openProject, group: .fileOps, title: "開く", tooltip: "プロジェクトを開く",
            iconKey: .openProject, shortcut: KeyboardShortcutSpec("o"),
            perform: { context in ProjectFileActions.promptOpen(store: context.store) }
        ),
        EditorCommand(
            id: .saveProject, group: .fileOps, title: "保存", tooltip: "プロジェクトを保存",
            iconKey: .saveProject, shortcut: KeyboardShortcutSpec("s"),
            perform: { context in ProjectFileActions.save(store: context.store) }
        ),
        EditorCommand(
            id: .saveProjectAs, group: .fileOps, title: "名前を付けて保存", tooltip: "名前を付けて保存",
            iconKey: .saveProjectAs, shortcut: KeyboardShortcutSpec("s", modifiers: [.command, .shift]),
            perform: { context in ProjectFileActions.promptSaveAs(store: context.store) }
        ),
        EditorCommand(
            id: .projectSettings, group: .project, title: "プロジェクト設定", tooltip: "プロジェクト設定",
            iconKey: .projectSettings, shortcut: nil,
            perform: { context in context.store.isShowingProjectSettings = true }
        ),
        unimplementedCommand(
            id: .videoSettings, group: .project, title: "動画設定", tooltip: "動画設定",
            iconKey: .videoSettings
        ),
        EditorCommand(
            id: .exportVideo, group: .project, title: "動画出力", tooltip: "動画出力",
            iconKey: .exportVideo, shortcut: KeyboardShortcutSpec("e", modifiers: [.command, .shift]),
            isEnabled: { context in context.store.currentTimeline.duration > 0 },
            perform: { context in context.store.isShowingExport = true }
        ),
        unimplementedCommand(
            id: .exportThumbnail, group: .project, title: "サムネイル画像出力", tooltip: "サムネイル画像出力",
            iconKey: .exportThumbnail
        ),
        unimplementedCommand(
            id: .copyThumbnail, group: .project, title: "サムネイルをコピー", tooltip: "サムネイル画像をクリップボードへコピー",
            iconKey: .copyThumbnail
        ),
        EditorCommand(
            id: .manageCharacters, group: .project, title: "キャラクター管理", tooltip: "キャラクター管理",
            iconKey: .addCharacter, shortcut: nil,
            perform: { context in context.store.isShowingCharacterManager = true }
        )
    ]

    // MARK: - History

    private static let historyCommands: [EditorCommand] = [
        EditorCommand(
            id: .undo, group: .history, title: "取り消す", tooltip: "取り消す",
            iconKey: .undo, shortcut: KeyboardShortcutSpec("z"),
            isEnabled: { $0.store.canUndo },
            perform: { $0.store.undo() }
        ),
        EditorCommand(
            id: .redo, group: .history, title: "やり直す", tooltip: "やり直す",
            iconKey: .redo, shortcut: KeyboardShortcutSpec("z", modifiers: [.command, .shift]),
            isEnabled: { $0.store.canRedo },
            perform: { $0.store.redo() }
        )
    ]

    // MARK: - Clipboard / timeline edit

    private static let clipboardEditCommands: [EditorCommand] = [
        EditorCommand(
            id: .cut, group: .clipboard, title: "切り取り", tooltip: "切り取り",
            iconKey: .cut, shortcut: KeyboardShortcutSpec("x"),
            isEnabled: { hasUnlockedSelection($0) },
            perform: { $0.store.cutSelected() }
        ),
        EditorCommand(
            id: .copy, group: .clipboard, title: "コピー", tooltip: "コピー",
            iconKey: .copy, shortcut: KeyboardShortcutSpec("c"),
            isEnabled: { !$0.store.selectedClipIDs.isEmpty },
            perform: { $0.store.copySelected() }
        ),
        EditorCommand(
            id: .paste, group: .clipboard, title: "貼り付け", tooltip: "貼り付け",
            iconKey: .paste, shortcut: KeyboardShortcutSpec("v"),
            isEnabled: { !$0.store.clipboard.isEmpty },
            perform: { $0.store.pasteClipboard() }
        ),
        EditorCommand(
            id: .splitAtPlayhead, group: .timelineEdit, title: "分割", tooltip: "再生位置で分割",
            iconKey: .split, shortcut: KeyboardShortcutSpec("b"),
            perform: { $0.store.splitAtPlayhead() }
        ),
        EditorCommand(
            id: .duplicate, group: .timelineEdit, title: "複製", tooltip: "複製",
            iconKey: .duplicate, shortcut: KeyboardShortcutSpec("d"),
            isEnabled: { hasUnlockedSelection($0) },
            perform: { $0.store.duplicateSelected() }
        ),
        EditorCommand(
            id: .toggleLock, group: .timelineEdit, title: "ロック", tooltip: "ロック/ロック解除",
            iconKey: .lock, shortcut: nil,
            isEnabled: { !$0.store.selectedClipIDs.isEmpty },
            perform: { $0.store.toggleLockSelected() }
        ),
        EditorCommand(
            id: .selectAll, group: .timelineEdit, title: "すべて選択", tooltip: "すべて選択",
            iconKey: .selectAll, shortcut: KeyboardShortcutSpec("a"),
            isEnabled: { !$0.store.currentTimeline.tracks.allSatisfy { $0.clips.isEmpty } },
            perform: { $0.store.selectAll() }
        ),
        EditorCommand(
            id: .delete, group: .timelineEdit, title: "削除", tooltip: "削除",
            iconKey: .delete, shortcut: KeyboardShortcutSpec(.delete, modifiers: []),
            isEnabled: { hasUnlockedSelection($0) },
            perform: { $0.store.deleteSelected() }
        ),
        EditorCommand(
            id: .rippleDelete, group: .timelineEdit, title: "削除して左詰め", tooltip: "削除して左詰め",
            iconKey: .rippleDelete, shortcut: nil,
            isEnabled: { hasUnlockedSelection($0) },
            perform: { $0.store.rippleDeleteSelected() }
        ),
        EditorCommand(
            id: .selectAllLeft, group: .timelineEdit, title: "左側をすべて選択", tooltip: "左側のアイテムをすべて選択",
            iconKey: .selectLeft, shortcut: nil,
            perform: { $0.store.selectAllLeftOfPlayhead() }
        ),
        EditorCommand(
            id: .selectAllRight, group: .timelineEdit, title: "右側をすべて選択", tooltip: "右側のアイテムをすべて選択",
            iconKey: .selectRight, shortcut: nil,
            perform: { $0.store.selectAllRightOfPlayhead() }
        ),
        EditorCommand(
            id: .bulkEdit, group: .timelineEdit, title: "一括編集", tooltip: "条件を指定して一括選択・置換",
            iconKey: .bulkEdit, shortcut: nil,
            perform: { $0.store.isShowingBulkEdit = true }
        )
    ]

    private static func hasUnlockedSelection(_ context: EditorContext) -> Bool {
        context.store.selectedClips.contains { !$0.isLocked }
    }

    // MARK: - Playback

    private static let playbackCommands: [EditorCommand] = [
        EditorCommand(
            id: .togglePlayback, group: .playback, title: "再生／停止", tooltip: "再生／停止",
            iconKey: .play, shortcut: KeyboardShortcutSpec(.space, modifiers: []),
            isOn: { $0.store.isPlaying },
            perform: { $0.store.isPlaying.toggle() }
        )
    ]

    // MARK: - Timeline helper toggles

    private static let timelineHelperCommands: [EditorCommand] = [
        EditorCommand(
            id: .clipAboveOnly, group: .view, title: "上のアイテムでクリッピング", tooltip: "上のアイテムを基準にしたクリッピング",
            iconKey: .clipAboveOnly, shortcut: nil,
            isOn: { $0.store.isClipAboveOnlyEnabled },
            perform: { $0.store.isClipAboveOnlyEnabled.toggle() }
        ),
        EditorCommand(
            id: .togglePreviewDirectManipulation, group: .view, title: "プレビュー直接操作", tooltip: "プレビュー上の直接操作を有効/無効",
            iconKey: .previewDirectManipulation, shortcut: nil,
            isOn: { $0.store.isPreviewDirectManipulationEnabled },
            perform: { $0.store.isPreviewDirectManipulationEnabled.toggle() }
        ),
        EditorCommand(
            id: .toggleSnap, group: .view, title: "スナップ", tooltip: "グリッド/スナップ",
            iconKey: .snap, shortcut: nil,
            isOn: { $0.store.isSnapEnabled },
            perform: { $0.store.isSnapEnabled.toggle() }
        )
    ]

    // MARK: - Add item

    private static let addItemCommands: [EditorCommand] = [
        EditorCommand(
            id: .addTextItem, group: .itemInsert, title: "テキスト", tooltip: "テキストアイテム",
            iconKey: .addText, shortcut: nil,
            perform: { $0.store.addTextItem() }
        ),
        EditorCommand(
            id: .addVoiceItem, group: .itemInsert, title: "ボイス", tooltip: "ボイスアイテム",
            iconKey: .addVoice, shortcut: nil,
            // The voice-composing panel is always docked in the main window already;
            // this command exists for toolbar/menu/shortcut parity rather than opening a
            // second entry point.
            perform: { _ in }
        ),
        EditorCommand(
            id: .addImageItem, group: .itemInsert, title: "画像", tooltip: "画像アイテム",
            iconKey: .addImage, shortcut: nil,
            perform: { $0.store.promptAddImageItem() }
        ),
        EditorCommand(
            id: .addAudioItem, group: .itemInsert, title: "音声", tooltip: "音声アイテム",
            iconKey: .addAudio, shortcut: nil,
            perform: { $0.store.promptAddAudioItem() }
        ),
        EditorCommand(
            id: .addCharacterItem, group: .itemInsert, title: "立ち絵", tooltip: "立ち絵アイテム",
            iconKey: .addCharacter, shortcut: nil,
            isEnabled: { !$0.store.project.characters.isEmpty },
            perform: { $0.store.addCharacterItem() }
        ),
        EditorCommand(
            id: .addVideoItem, group: .itemInsert, title: "動画", tooltip: "動画アイテム",
            iconKey: .addVideo, shortcut: nil,
            perform: { $0.store.promptAddVideoItem() }
        ),
        unimplementedCommand(id: .addShapeItem, group: .itemInsert, title: "図形", tooltip: "図形アイテム", iconKey: .addShape),
        unimplementedCommand(id: .addExpressionItem, group: .itemInsert, title: "表情", tooltip: "表情アイテム", iconKey: .addExpression),
        unimplementedCommand(id: .addEffectItem, group: .itemInsert, title: "エフェクト", tooltip: "エフェクトアイテム", iconKey: .addEffect),
        unimplementedCommand(id: .addTransitionItem, group: .itemInsert, title: "場面切り替え", tooltip: "場面切り替えアイテム", iconKey: .addTransition),
        unimplementedCommand(id: .addSceneItem, group: .itemInsert, title: "シーン", tooltip: "シーンアイテム", iconKey: .addScene),
        unimplementedCommand(id: .addScreenCaptureItem, group: .itemInsert, title: "画面キャプチャ", tooltip: "画面複製/画面キャプチャ", iconKey: .addScreenCapture),
        unimplementedCommand(id: .addGroupControlItem, group: .itemInsert, title: "グループ制御", tooltip: "グループ制御アイテム", iconKey: .addGroupControl),
        unimplementedCommand(id: .addFromTemplate, group: .itemInsert, title: "テンプレート", tooltip: "テンプレートから追加", iconKey: .addTemplate),
        unimplementedCommand(id: .addFromRecent, group: .itemInsert, title: "最近使ったファイル", tooltip: "最近使ったファイル", iconKey: .addRecent)
    ]
}
