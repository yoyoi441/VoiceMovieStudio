import Foundation

/// Every command the editor exposes through a toolbar button, a menu item, and/or a
/// keyboard shortcut. Having one id per command (rather than each surface inventing its
/// own action closure) is what lets `ToolbarButton`, `.commands`, and a future context
/// menu all stay in sync automatically — see `CommandRegistry`.
enum CommandID: String, CaseIterable, Hashable, Sendable {
    // File / project
    case newProject
    case openProject
    case saveProject
    case saveProjectAs
    case projectSettings
    case videoSettings
    case exportVideo
    case exportThumbnail
    case copyThumbnail
    case manageCharacters

    // History / clipboard / edit
    case undo
    case redo
    case cut
    case copy
    case paste
    case splitAtPlayhead
    case duplicate
    case toggleLock
    case selectAll
    case delete
    case rippleDelete
    case selectAllLeft
    case selectAllRight
    case bulkEdit

    // Playback
    case togglePlayback

    // Timeline helpers
    case clipAboveOnly
    case togglePreviewDirectManipulation
    case toggleSnap

    // Add item
    case addVoiceItem
    case addTextItem
    case addVideoItem
    case addAudioItem
    case addImageItem
    case addShapeItem
    case addCharacterItem
    case addExpressionItem
    case addEffectItem
    case addTransitionItem
    case addSceneItem
    case addScreenCaptureItem
    case addGroupControlItem
    case addFromTemplate
    case addFromRecent
}

enum CommandGroupKind: Hashable, Sendable {
    case fileOps
    case history
    case clipboard
    case timelineEdit
    case playback
    case itemInsert
    case view
    case project
}
