import Foundation

/// A mouth shape used for lip-sync. The model can be extended with more parts (blink, eyebrows,
/// hands, etc.) — this is deliberately just the three shapes needed for basic lip-sync;
/// the enum is the extension point when more parts are added later.
public enum MouthShape: String, Codable, CaseIterable, Sendable {
    case closed
    case small
    case open
}

public enum EyeShape: String, Codable, CaseIterable, Sendable {
    case open
    case closed
}

/// One ordered image in a character's mouth or eye animation. Frames are stored from
/// mouth closed -> open and eye open -> closed. `sourceLayerID` keeps a PSD assignment
/// connected to the layer it came from while `imageFileName` remains usable by ordinary
/// image-based characters and by older projects.
public struct CharacterPartFrame: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var imageFileName: String?
    public var sourceLayerID: UUID?
    /// A frame may be composed from multiple PSD layers, such as a white-eye layer and
    /// an iris layer. Optional storage keeps projects written by earlier versions valid.
    public var sourceLayerIDs: [UUID]?

    public init(
        id: UUID = UUID(),
        name: String,
        imageFileName: String? = nil,
        sourceLayerID: UUID? = nil,
        sourceLayerIDs: [UUID]? = nil
    ) {
        self.id = id
        self.name = name
        self.imageFileName = imageFileName
        self.sourceLayerID = sourceLayerID
        self.sourceLayerIDs = sourceLayerIDs
    }

    public var allSourceLayerIDs: [UUID] {
        if let sourceLayerIDs, !sourceLayerIDs.isEmpty { return sourceLayerIDs }
        return sourceLayerID.map { [$0] } ?? []
    }
}

public enum CharacterPartKind: String, Codable, CaseIterable, Sendable {
    case mouth
    case eye
}

public struct CharacterExpression: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var imageFileName: String
    /// PSD expressions can keep a matching image with animated mouth/eye folders removed.
    /// Older expressions omit this and safely fall back to the character animation base.
    public var animationBaseImageFileName: String? = nil

    public init(id: UUID = UUID(), name: String, imageFileName: String, animationBaseImageFileName: String? = nil) {
        self.id = id
        self.name = name
        self.imageFileName = imageFileName
        self.animationBaseImageFileName = animationBaseImageFileName
    }
}

public struct CharacterPreset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var baseImageFileName: String
    public var mouthImageFileNames: [MouthShape: String]
    public var eyeImageFileNames: [EyeShape: String]
    public var defaultExpressionID: UUID?
    public var layerVisibility: [UUID: Bool]
    public var animationDefaults: CharacterAnimationDefaults?
    public var voice: CharacterVoicePreset? = nil
    /// Optional so presets saved by previous versions continue to decode. When absent,
    /// the fixed legacy mouth/eye dictionaries above are expanded into standard frames.
    public var mouthAnimationFrames: [CharacterPartFrame]? = nil
    public var eyeAnimationFrames: [CharacterPartFrame]? = nil
    public var animationBaseImageFileName: String? = nil

    public init(id: UUID = UUID(), name: String, baseImageFileName: String, mouthImageFileNames: [MouthShape: String], eyeImageFileNames: [EyeShape: String], defaultExpressionID: UUID?, layerVisibility: [UUID: Bool], animationDefaults: CharacterAnimationDefaults? = nil, mouthAnimationFrames: [CharacterPartFrame]? = nil, eyeAnimationFrames: [CharacterPartFrame]? = nil, animationBaseImageFileName: String? = nil) {
        self.id = id
        self.name = name
        self.baseImageFileName = baseImageFileName
        self.mouthImageFileNames = mouthImageFileNames
        self.eyeImageFileNames = eyeImageFileNames
        self.defaultExpressionID = defaultExpressionID
        self.layerVisibility = layerVisibility
        self.animationDefaults = animationDefaults
        self.mouthAnimationFrames = mouthAnimationFrames
        self.eyeAnimationFrames = eyeAnimationFrames
        self.animationBaseImageFileName = animationBaseImageFileName
    }
}

public struct CharacterAnimationDefaults: Codable, Hashable, Sendable {
    public var mouthSpeed: Double
    public var flipHorizontal: Bool
    public var blinkEnabled: Bool
    public var blinkInterval: Double
    public var blinkDuration: Double

    public init(character: Character) {
        mouthSpeed = character.defaultMouthSpeed
        flipHorizontal = character.defaultFlipHorizontal
        blinkEnabled = character.blinkEnabled
        blinkInterval = character.blinkInterval
        blinkDuration = character.blinkDuration
    }
}

/// §7-6 "立ち絵の種類". Only `simple` (a single base image + mouth-shape overlays) has
/// real rendering support today; `animated`/`psd` are selectable and keep their file
/// reference so a project round-trips, but `CompositeFrameView` treats them like `simple`
/// until PSD parsing / animated-part playback exists.
public enum TachieKind: String, Codable, CaseIterable, Sendable {
    case none
    case simple
    case animated
    case psd

    public var displayName: String {
        switch self {
        case .none: return "表示しない"
        case .simple: return "シンプル立ち絵"
        case .animated: return "動く立ち絵"
        case .psd: return "PSD形式の立ち絵"
        }
    }

    public static var selectableCases: [TachieKind] { [.none, .animated, .psd] }

    public var isImplemented: Bool { self != .none }
}

/// §7-6 layer tree node. Inert placeholder structure (no PSD parsing exists to populate
/// it from real layer data) so the tree UI — expand/collapse, folders, visibility,
/// selection — has something real to operate on ahead of that.
public struct TachieLayerNode: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isVisible: Bool
    public var isFolder: Bool
    public var children: [TachieLayerNode]
    public var imageFileName: String?
    /// Original sibling position in the imported PSD (0 is visually topmost).
    public var sourceOrder: Int?

    public init(id: UUID = UUID(), name: String, isVisible: Bool = true, isFolder: Bool = false, children: [TachieLayerNode] = [], imageFileName: String? = nil, sourceOrder: Int? = nil) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isFolder = isFolder
        self.children = children
        self.imageFileName = imageFileName
        self.sourceOrder = sourceOrder
    }
}

/// A "tachie" (立ち絵) character: a base image plus swappable mouth-shape overlays.
/// Mouth images are expected to be the same pixel dimensions as the base image (the usual
/// convention for layered tachie art and PSD-style parts) so they're composited by
/// drawing them in the exact same rect as the base — no separate anchor point needed.
public struct Character: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// §7-7 grouping/identification — purely organizational, doesn't affect rendering.
    public var groupName: String
    public var displayColor: CodableColor
    public var tachieKind: TachieKind
    /// File name of the base body/face image, relative to the project's Assets directory.
    public var baseImageFileName: String
    /// File names of mouth overlay images, keyed by shape, relative to the project's Assets directory.
    public var mouthImageFileNames: [MouthShape: String]
    public var eyeImageFileNames: [EyeShape: String]
    /// Ordered, user-extensible animation frames. The legacy dictionaries remain in the
    /// file format and are synchronized to the closed/middle/open compatibility points.
    public var mouthAnimationFrames: [CharacterPartFrame]
    public var eyeAnimationFrames: [CharacterPartFrame]
    /// Full-canvas PSD composite with the animated mouth/eye categories removed.
    /// Preview and export draw the selected frames over this image, preventing the
    /// originally visible PSD parts from remaining underneath.
    public var animationBaseImageFileName: String?
    public var expressions: [CharacterExpression]
    public var presets: [CharacterPreset]
    public var defaultExpressionID: UUID?
    public var layerTree: [TachieLayerNode]
    /// Default voice engine speaker + synthesis parameters for this character, used to
    /// pre-fill the voice panel/inspector when this character is selected.
    public var defaultSpeakerID: Int?
    public var defaultVoiceSettings: VoiceSettings
    /// Character-specific lip-sync tempo. 1.0 follows the source mora duration;
    /// larger values return the mouth to closed sooner.
    public var defaultMouthSpeed: Double
    /// Applied to newly created timeline items for this character.
    public var defaultFlipHorizontal: Bool
    public var blinkEnabled: Bool
    public var blinkInterval: Double
    public var blinkDuration: Double
    /// Original imported profile metadata is retained even when this version cannot render the
    /// corresponding plug-in/effect. This makes imports non-destructive and allows a
    /// future compatibility update to re-interpret the settings without re-importing.
    public var importedSource: String?
    public var importedSourceID: String?
    public var importedRawJSON: String?
    public var shortcut: String
    public var preferredLayer: Int
    public var voiceProvider: String
    public var voiceLibrary: String
    public var voiceStyle: String
    public var usageTerms: String
    public var credit: CreditMetadata

    public init(
        id: UUID = UUID(),
        name: String,
        groupName: String = "",
        displayColor: CodableColor = CodableColor(red: 0.6, green: 0.8, blue: 1.0),
        tachieKind: TachieKind = .animated,
        baseImageFileName: String,
        mouthImageFileNames: [MouthShape: String] = [:],
        eyeImageFileNames: [EyeShape: String] = [:],
        expressions: [CharacterExpression] = [],
        presets: [CharacterPreset] = [],
        defaultExpressionID: UUID? = nil,
        layerTree: [TachieLayerNode] = [],
        defaultSpeakerID: Int? = nil,
        defaultVoiceSettings: VoiceSettings = VoiceSettings(),
        defaultMouthSpeed: Double = 1.0,
        defaultFlipHorizontal: Bool = false,
        blinkEnabled: Bool = true,
        blinkInterval: Double = 3.2,
        blinkDuration: Double = 0.18,
        importedSource: String? = nil,
        importedSourceID: String? = nil,
        importedRawJSON: String? = nil,
        shortcut: String = "",
        preferredLayer: Int = 0,
        voiceProvider: String = "",
        voiceLibrary: String = "",
        voiceStyle: String = "",
        usageTerms: String = "",
        credit: CreditMetadata = CreditMetadata(),
        mouthAnimationFrames: [CharacterPartFrame]? = nil,
        eyeAnimationFrames: [CharacterPartFrame]? = nil,
        animationBaseImageFileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.groupName = groupName
        self.displayColor = displayColor
        self.tachieKind = tachieKind
        self.baseImageFileName = baseImageFileName
        self.mouthImageFileNames = mouthImageFileNames
        self.eyeImageFileNames = eyeImageFileNames
        self.mouthAnimationFrames = mouthAnimationFrames ?? Self.defaultMouthAnimationFrames(images: mouthImageFileNames)
        self.eyeAnimationFrames = eyeAnimationFrames ?? Self.defaultEyeAnimationFrames(images: eyeImageFileNames)
        self.animationBaseImageFileName = animationBaseImageFileName
        self.expressions = expressions
        self.presets = presets
        self.defaultExpressionID = defaultExpressionID
        self.layerTree = layerTree.isEmpty ? Self.defaultLayerTree(mouthImageFileNames: mouthImageFileNames) : layerTree
        self.defaultSpeakerID = defaultSpeakerID
        self.defaultVoiceSettings = defaultVoiceSettings
        self.defaultMouthSpeed = min(max(defaultMouthSpeed, 0.5), 3.0)
        self.defaultFlipHorizontal = defaultFlipHorizontal
        self.blinkEnabled = blinkEnabled
        self.blinkInterval = blinkInterval.isFinite ? min(max(blinkInterval, 0.5), 20) : 3.2
        self.blinkDuration = blinkDuration.isFinite ? min(max(blinkDuration, 0.05), 0.5) : 0.18
        self.importedSource = importedSource
        self.importedSourceID = importedSourceID
        self.importedRawJSON = importedRawJSON
        self.shortcut = shortcut
        self.preferredLayer = preferredLayer
        self.voiceProvider = voiceProvider
        self.voiceLibrary = voiceLibrary
        self.voiceStyle = voiceStyle
        self.usageTerms = usageTerms
        self.credit = credit
        self.synchronizeLegacyAnimationImages()
    }

    private enum CodingKeys: String, CodingKey {
        case blinkEnabled, blinkInterval, blinkDuration
        case id, name, groupName, displayColor, tachieKind, baseImageFileName
        case mouthImageFileNames, eyeImageFileNames, mouthAnimationFrames, eyeAnimationFrames, animationBaseImageFileName
        case expressions, presets, defaultExpressionID, layerTree, defaultSpeakerID, defaultVoiceSettings, defaultMouthSpeed, defaultFlipHorizontal
        case importedSource, importedSourceID, importedRawJSON, shortcut, preferredLayer
        case voiceProvider, voiceLibrary, voiceStyle, usageTerms, credit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        displayColor = try c.decodeIfPresent(CodableColor.self, forKey: .displayColor) ?? CodableColor(red: 0.6, green: 0.8, blue: 1)
        tachieKind = try c.decodeIfPresent(TachieKind.self, forKey: .tachieKind) ?? .simple
        baseImageFileName = try c.decodeIfPresent(String.self, forKey: .baseImageFileName) ?? ""
        mouthImageFileNames = try c.decodeIfPresent([MouthShape: String].self, forKey: .mouthImageFileNames) ?? [:]
        eyeImageFileNames = try c.decodeIfPresent([EyeShape: String].self, forKey: .eyeImageFileNames) ?? [:]
        mouthAnimationFrames = try c.decodeIfPresent([CharacterPartFrame].self, forKey: .mouthAnimationFrames)
            ?? Self.defaultMouthAnimationFrames(images: mouthImageFileNames)
        eyeAnimationFrames = try c.decodeIfPresent([CharacterPartFrame].self, forKey: .eyeAnimationFrames)
            ?? Self.defaultEyeAnimationFrames(images: eyeImageFileNames)
        animationBaseImageFileName = try c.decodeIfPresent(String.self, forKey: .animationBaseImageFileName)
        expressions = try c.decodeIfPresent([CharacterExpression].self, forKey: .expressions) ?? []
        presets = try c.decodeIfPresent([CharacterPreset].self, forKey: .presets) ?? []
        defaultExpressionID = try c.decodeIfPresent(UUID.self, forKey: .defaultExpressionID)
        layerTree = try c.decodeIfPresent([TachieLayerNode].self, forKey: .layerTree) ?? []
        defaultSpeakerID = try c.decodeIfPresent(Int.self, forKey: .defaultSpeakerID)
        defaultVoiceSettings = try c.decodeIfPresent(VoiceSettings.self, forKey: .defaultVoiceSettings) ?? VoiceSettings()
        defaultMouthSpeed = min(max(try c.decodeIfPresent(Double.self, forKey: .defaultMouthSpeed) ?? 1.0, 0.5), 3.0)
        defaultFlipHorizontal = try c.decodeIfPresent(Bool.self, forKey: .defaultFlipHorizontal) ?? false
        blinkEnabled = try c.decodeIfPresent(Bool.self, forKey: .blinkEnabled) ?? true
        blinkInterval = min(max(try c.decodeIfPresent(Double.self, forKey: .blinkInterval) ?? 3.2, 0.5), 20)
        blinkDuration = min(max(try c.decodeIfPresent(Double.self, forKey: .blinkDuration) ?? 0.18, 0.05), 0.5)
        importedSource = try c.decodeIfPresent(String.self, forKey: .importedSource)
        importedSourceID = try c.decodeIfPresent(String.self, forKey: .importedSourceID)
        importedRawJSON = try c.decodeIfPresent(String.self, forKey: .importedRawJSON)
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
        preferredLayer = try c.decodeIfPresent(Int.self, forKey: .preferredLayer) ?? 0
        voiceProvider = try c.decodeIfPresent(String.self, forKey: .voiceProvider) ?? ""
        voiceLibrary = try c.decodeIfPresent(String.self, forKey: .voiceLibrary) ?? ""
        voiceStyle = try c.decodeIfPresent(String.self, forKey: .voiceStyle) ?? ""
        usageTerms = try c.decodeIfPresent(String.self, forKey: .usageTerms) ?? ""
        credit = try c.decodeIfPresent(CreditMetadata.self, forKey: .credit) ?? CreditMetadata(title: name)
        synchronizeLegacyAnimationImages()
        reconnectPSDAnimationFrameSources()
    }

    public func eyeShape(at time: Double) -> EyeShape {
        guard blinkEnabled, time.isFinite else { return .open }
        let interval = blinkInterval.isFinite ? max(0.5, blinkInterval) : 3.2
        let duration = blinkDuration.isFinite ? min(max(blinkDuration, 0.05), interval / 2) : 0.18
        return max(0, time).truncatingRemainder(dividingBy: interval) >= interval - duration ? .closed : .open
    }

    /// Returns the animation frame used at a given blink phase. Existing two-frame
    /// characters retain their previous open/closed timing; three or more frames travel
    /// through every intermediate image while closing and opening.
    public func eyeAnimationFrameIndex(at time: Double) -> Int {
        let count = eyeAnimationFrames.count
        guard count > 1, blinkEnabled, time.isFinite else { return 0 }
        if count == 2 { return eyeShape(at: time) == .closed ? 1 : 0 }
        let interval = blinkInterval.isFinite ? max(0.5, blinkInterval) : 3.2
        let duration = blinkDuration.isFinite ? min(max(blinkDuration, 0.05), interval / 2) : 0.18
        let remainder = max(0, time).truncatingRemainder(dividingBy: interval)
        let start = interval - duration
        guard remainder >= start else { return 0 }
        let phase = min(1, max(0, (remainder - start) / duration))
        let closedAmount = phase <= 0.5 ? phase * 2 : (1 - phase) * 2
        return min(count - 1, max(0, Int((closedAmount * Double(count - 1)).rounded())))
    }

    public func mouthAnimationFileName(at index: Int) -> String? {
        Self.nearestAssignedFile(in: mouthAnimationFrames, to: index)
    }

    public func eyeAnimationFileName(at index: Int) -> String? {
        Self.nearestAssignedFile(in: eyeAnimationFrames, to: index)
    }

    public static func defaultMouthAnimationFrames(images: [MouthShape: String]) -> [CharacterPartFrame] {
        [
            CharacterPartFrame(name: "通常", imageFileName: images[.closed]),
            CharacterPartFrame(name: "小", imageFileName: images[.small]),
            CharacterPartFrame(name: "開", imageFileName: images[.open])
        ]
    }

    public static func defaultEyeAnimationFrames(images: [EyeShape: String]) -> [CharacterPartFrame] {
        [
            CharacterPartFrame(name: "開", imageFileName: images[.open]),
            CharacterPartFrame(name: "閉", imageFileName: images[.closed])
        ]
    }

    /// Keeps old readers, imported profiles, and the existing three-state lip-sync model
    /// functional after users add any number of visual in-between frames.
    public mutating func synchronizeLegacyAnimationImages() {
        mouthImageFileNames = [:]
        if let file = Self.assignedFile(in: mouthAnimationFrames, at: 0) {
            mouthImageFileNames[.closed] = file
        }
        if let file = Self.assignedFile(in: mouthAnimationFrames, at: Self.middleIndex(mouthAnimationFrames.count)) {
            mouthImageFileNames[.small] = file
        }
        if let file = Self.assignedFile(in: mouthAnimationFrames, at: max(0, mouthAnimationFrames.count - 1)) {
            mouthImageFileNames[.open] = file
        }
        eyeImageFileNames = [:]
        if let file = Self.assignedFile(in: eyeAnimationFrames, at: 0) {
            eyeImageFileNames[.open] = file
        }
        if let file = Self.assignedFile(in: eyeAnimationFrames, at: max(0, eyeAnimationFrames.count - 1)) {
            eyeImageFileNames[.closed] = file
        }
    }

    /// Reconnects animation frames saved by versions that only stored an extracted PNG
    /// file name. The PSD tree already retains that file-to-layer relationship, so this
    /// migration can recover the source IDs without asking the user to set every slot
    /// again. Folder composites cannot be inferred and remain intentionally unassigned.
    @discardableResult
    public mutating func reconnectPSDAnimationFrameSources() -> Bool {
        guard tachieKind == .psd else { return false }
        var layerIDByFileName: [String: UUID] = [:]
        func collect(_ nodes: [TachieLayerNode]) {
            for node in nodes {
                if let fileName = node.imageFileName {
                    layerIDByFileName[fileName] = node.id
                }
                collect(node.children)
            }
        }
        collect(layerTree)

        var changed = false
        for index in mouthAnimationFrames.indices
            where mouthAnimationFrames[index].sourceLayerID == nil {
            if let fileName = mouthAnimationFrames[index].imageFileName,
               let layerID = layerIDByFileName[fileName] {
                mouthAnimationFrames[index].sourceLayerID = layerID
                mouthAnimationFrames[index].sourceLayerIDs = [layerID]
                changed = true
            }
        }
        for index in eyeAnimationFrames.indices
            where eyeAnimationFrames[index].sourceLayerID == nil {
            if let fileName = eyeAnimationFrames[index].imageFileName,
               let layerID = layerIDByFileName[fileName] {
                eyeAnimationFrames[index].sourceLayerID = layerID
                eyeAnimationFrames[index].sourceLayerIDs = [layerID]
                changed = true
            }
        }
        return changed
    }

    public static func mouthCompatibilityIndex(_ shape: MouthShape, frameCount: Int) -> Int {
        switch shape {
        case .closed: return 0
        case .small: return middleIndex(frameCount)
        case .open: return max(0, frameCount - 1)
        }
    }

    public static func eyeCompatibilityIndex(_ shape: EyeShape, frameCount: Int) -> Int {
        shape == .open ? 0 : max(0, frameCount - 1)
    }

    private static func middleIndex(_ count: Int) -> Int {
        guard count > 1 else { return 0 }
        return Int((Double(count - 1) * 0.5).rounded())
    }

    private static func nearestAssignedFile(in frames: [CharacterPartFrame], to requestedIndex: Int) -> String? {
        guard !frames.isEmpty else { return nil }
        let target = min(frames.count - 1, max(0, requestedIndex))
        return frames.enumerated()
            .filter { $0.element.imageFileName != nil }
            .min { lhs, rhs in
                let leftDistance = abs(lhs.offset - target)
                let rightDistance = abs(rhs.offset - target)
                return leftDistance == rightDistance ? lhs.offset < rhs.offset : leftDistance < rightDistance
            }?.element.imageFileName
    }

    private static func assignedFile(in frames: [CharacterPartFrame], at index: Int) -> String? {
        guard frames.indices.contains(index) else { return nil }
        return frames[index].imageFileName
    }

    /// A plausible-looking default tree (base + a mouth folder) so new characters don't
    /// start with an empty layer panel.
    private static func defaultLayerTree(mouthImageFileNames: [MouthShape: String]) -> [TachieLayerNode] {
        var nodes = [TachieLayerNode(name: "ベース")]
        if !mouthImageFileNames.isEmpty {
            let mouthChildren = MouthShape.allCases.compactMap { shape -> TachieLayerNode? in
                guard mouthImageFileNames[shape] != nil else { return nil }
                return TachieLayerNode(name: shape.rawValue)
            }
            nodes.append(TachieLayerNode(name: "口", isFolder: true, children: mouthChildren))
        }
        return nodes
    }
}

/// Resolves which PSD subtrees must be absent from the static base image once mouth or
/// eye frames are assigned. A semantic category folder (for example `!口` or `!目`) is
/// preferred over individual leaves so the originally visible sibling cannot remain
/// baked underneath a newly selected frame.
public enum CharacterPartLayerResolver {
    public static func exclusionLayerIDs(for character: Character) -> Set<UUID> {
        var result = categoryRoots(
            for: character.mouthAnimationFrames.flatMap(\.allSourceLayerIDs),
            in: character.layerTree,
            category: .mouth
        )
        result.formUnion(categoryRoots(
            for: character.eyeAnimationFrames.flatMap(\.allSourceLayerIDs),
            in: character.layerTree,
            category: .eye
        ))
        return minimized(result, in: character.layerTree)
    }

    private static func categoryRoots(
        for sourceIDs: [UUID],
        in tree: [TachieLayerNode],
        category: CharacterPartKind
    ) -> Set<UUID> {
        let uniqueIDs = Array(Set(sourceIDs))
        guard !uniqueIDs.isEmpty else { return [] }
        let paths = uniqueIDs.compactMap { path(to: $0, in: tree) }
        guard !paths.isEmpty else { return [] }

        let namedRoots = paths.compactMap { path in
            path.reversed().first { node in node.isFolder && isCategoryFolder(node.name, category: category) }?.id
        }
        if !namedRoots.isEmpty { return Set(namedRoots) }

        var common = paths[0]
        for path in paths.dropFirst() {
            common = Array(zip(common, path).prefix { $0.id == $1.id }.map(\.0))
        }
        if let folder = common.reversed().first(where: \.isFolder) { return [folder.id] }
        return Set(uniqueIDs)
    }

    private static func path(to id: UUID, in nodes: [TachieLayerNode]) -> [TachieLayerNode]? {
        for node in nodes {
            if node.id == id { return [node] }
            if let childPath = path(to: id, in: node.children) { return [node] + childPath }
        }
        return nil
    }

    private static func isCategoryFolder(_ name: String, category: CharacterPartKind) -> Bool {
        let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: "!*#@ \t")).lowercased()
        switch category {
        case .mouth: return cleaned == "口" || cleaned == "mouth"
        case .eye: return cleaned == "目" || cleaned == "eye" || cleaned == "eyes"
        }
    }

    private static func minimized(_ ids: Set<UUID>, in tree: [TachieLayerNode]) -> Set<UUID> {
        ids.filter { candidate in
            guard let candidatePath = path(to: candidate, in: tree) else { return false }
            return !candidatePath.dropLast().contains { ids.contains($0.id) }
        }
    }
}
