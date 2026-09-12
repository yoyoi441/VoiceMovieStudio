import SwiftUI
import AppKit

/// Every icon the editor UI uses is looked up by key, never by a literal SF Symbol name
/// scattered through view code. That's the whole point: when real artwork arrives, drop
/// images named exactly like each key's `rawValue` into `Assets.xcassets` and every button
/// picks them up automatically — no view code changes. See `IconCatalog.resolve(_:)`.
struct IconKey: RawRepresentable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

extension IconKey {
    // File
    static let newProject = IconKey(rawValue: "newProject")
    static let openProject = IconKey(rawValue: "openProject")
    static let saveProject = IconKey(rawValue: "saveProject")
    static let saveProjectAs = IconKey(rawValue: "saveProjectAs")
    static let projectSettings = IconKey(rawValue: "projectSettings")
    static let videoSettings = IconKey(rawValue: "videoSettings")
    static let exportVideo = IconKey(rawValue: "exportVideo")
    static let exportThumbnail = IconKey(rawValue: "exportThumbnail")
    static let copyThumbnail = IconKey(rawValue: "copyThumbnail")

    // History / clipboard / edit
    static let undo = IconKey(rawValue: "undo")
    static let redo = IconKey(rawValue: "redo")
    static let cut = IconKey(rawValue: "cut")
    static let copy = IconKey(rawValue: "copy")
    static let paste = IconKey(rawValue: "paste")
    static let split = IconKey(rawValue: "split")
    static let duplicate = IconKey(rawValue: "duplicate")
    static let lock = IconKey(rawValue: "lock")
    static let unlock = IconKey(rawValue: "unlock")
    static let selectAll = IconKey(rawValue: "selectAll")
    static let delete = IconKey(rawValue: "delete")
    static let rippleDelete = IconKey(rawValue: "rippleDelete")
    static let selectLeft = IconKey(rawValue: "selectLeft")
    static let selectRight = IconKey(rawValue: "selectRight")
    static let bulkEdit = IconKey(rawValue: "bulkEdit")

    // Zoom
    static let zoomOut = IconKey(rawValue: "zoomOut")
    static let zoomIn = IconKey(rawValue: "zoomIn")
    static let zoomFit = IconKey(rawValue: "zoomFit")

    // Add item
    static let addVoice = IconKey(rawValue: "addVoice")
    static let addText = IconKey(rawValue: "addText")
    static let addVideo = IconKey(rawValue: "addVideo")
    static let addAudio = IconKey(rawValue: "addAudio")
    static let addImage = IconKey(rawValue: "addImage")
    static let addShape = IconKey(rawValue: "addShape")
    static let addCharacter = IconKey(rawValue: "addCharacter")
    static let addExpression = IconKey(rawValue: "addExpression")
    static let addEffect = IconKey(rawValue: "addEffect")
    static let addTransition = IconKey(rawValue: "addTransition")
    static let addScene = IconKey(rawValue: "addScene")
    static let addScreenCapture = IconKey(rawValue: "addScreenCapture")
    static let addGroupControl = IconKey(rawValue: "addGroupControl")
    static let addTemplate = IconKey(rawValue: "addTemplate")
    static let addRecent = IconKey(rawValue: "addRecent")

    // Timeline helpers
    static let clipAboveOnly = IconKey(rawValue: "clipAboveOnly")
    static let previewDirectManipulation = IconKey(rawValue: "previewDirectManipulation")
    static let snap = IconKey(rawValue: "snap")

    // Scene tab
    static let sceneAdd = IconKey(rawValue: "sceneAdd")
    static let sceneClose = IconKey(rawValue: "sceneClose")
    static let sceneMenu = IconKey(rawValue: "sceneMenu")

    // Misc / generic
    static let chevronExpanded = IconKey(rawValue: "chevronExpanded")
    static let chevronCollapsed = IconKey(rawValue: "chevronCollapsed")
    static let colorSwatch = IconKey(rawValue: "colorSwatch")
    static let reset = IconKey(rawValue: "reset")
    static let moveUp = IconKey(rawValue: "moveUp")
    static let moveDown = IconKey(rawValue: "moveDown")
    static let more = IconKey(rawValue: "more")
    static let folder = IconKey(rawValue: "folder")
    static let file = IconKey(rawValue: "file")
    static let visible = IconKey(rawValue: "visible")
    static let hidden = IconKey(rawValue: "hidden")
    static let addStop = IconKey(rawValue: "addStop")
    static let removeStop = IconKey(rawValue: "removeStop")
    static let play = IconKey(rawValue: "play")
    static let unimplemented = IconKey(rawValue: "unimplemented")
}

/// Resolves an `IconKey` to a displayable `Image`. Real artwork (an image asset in
/// `Assets.xcassets` whose name matches `key.rawValue`) always wins; until that arrives,
/// every key falls back to an SF Symbol so the UI is fully usable with placeholder icons.
enum IconCatalog {
    @MainActor
    static func resolve(_ key: IconKey) -> Image {
        if NSImage(named: key.rawValue) != nil {
            return Image(key.rawValue)
        }
        return Image(systemName: symbolNames[key] ?? "questionmark.square.dashed")
    }

    private static let symbolNames: [IconKey: String] = [
        .newProject: "doc.badge.plus",
        .openProject: "folder",
        .saveProject: "square.and.arrow.down",
        .saveProjectAs: "square.and.arrow.down.on.square",
        .projectSettings: "gearshape",
        .videoSettings: "film",
        .exportVideo: "square.and.arrow.up",
        .exportThumbnail: "photo",
        .copyThumbnail: "photo.on.rectangle",

        .undo: "arrow.uturn.backward",
        .redo: "arrow.uturn.forward",
        .cut: "scissors",
        .copy: "doc.on.doc",
        .paste: "clipboard",
        .split: "square.split.2x1",
        .duplicate: "plus.square.on.square",
        .lock: "lock",
        .unlock: "lock.open",
        .selectAll: "checkmark.rectangle.stack",
        .delete: "trash",
        .rippleDelete: "trash.square",
        .selectLeft: "arrow.left.to.line",
        .selectRight: "arrow.right.to.line",
        .bulkEdit: "rectangle.dashed.badge.record",

        .zoomOut: "minus.magnifyingglass",
        .zoomIn: "plus.magnifyingglass",
        .zoomFit: "arrow.up.left.and.arrow.down.right.rectangle",

        .addVoice: "waveform.circle",
        .addText: "textformat",
        .addVideo: "video",
        .addAudio: "speaker.wave.2",
        .addImage: "photo",
        .addShape: "square.on.circle",
        .addCharacter: "person.crop.rectangle",
        .addExpression: "face.smiling",
        .addEffect: "sparkles",
        .addTransition: "rectangle.2.swap",
        .addScene: "rectangle.stack",
        .addScreenCapture: "rectangle.inset.filled.and.person.filled",
        .addGroupControl: "square.stack.3d.up",
        .addTemplate: "doc.on.doc.fill",
        .addRecent: "clock",

        .clipAboveOnly: "square.stack.3d.up.badge.a",
        .previewDirectManipulation: "hand.point.up.left",
        .snap: "align.horizontal.left",

        .sceneAdd: "plus",
        .sceneClose: "xmark",
        .sceneMenu: "chevron.down",

        .chevronExpanded: "chevron.down",
        .chevronCollapsed: "chevron.right",
        .colorSwatch: "square.fill",
        .reset: "arrow.counterclockwise",
        .moveUp: "chevron.up",
        .moveDown: "chevron.down",
        .more: "ellipsis.circle",
        .folder: "folder",
        .file: "doc",
        .visible: "eye",
        .hidden: "eye.slash",
        .addStop: "plus.circle",
        .removeStop: "minus.circle",
        .play: "play.fill",
        .unimplemented: "hammer"
    ]
}
