import Foundation

public struct CharacterPartFrameSuggestion: Hashable, Sendable {
    public var name: String
    public var sourceLayerIDs: [UUID]

    public init(name: String, sourceLayerIDs: [UUID]) {
        self.name = name
        self.sourceLayerIDs = sourceLayerIDs
    }
}

public struct CharacterAnimationSetupSuggestion: Hashable, Sendable {
    public var mouthFrames: [CharacterPartFrameSuggestion]
    public var eyeFrames: [CharacterPartFrameSuggestion]

    public init(
        mouthFrames: [CharacterPartFrameSuggestion] = [],
        eyeFrames: [CharacterPartFrameSuggestion] = []
    ) {
        self.mouthFrames = mouthFrames
        self.eyeFrames = eyeFrames
    }
}

/// Finds a conservative default animation set from common PSD category structures.
/// Nothing is applied during import; the result is used only when the user presses the
/// automatic setup button. Unknown naming schemes remain empty instead of guessing.
public enum PSDCharacterAnimationDefaultDetector {
    public static func detect(in tree: [TachieLayerNode]) -> CharacterAnimationSetupSuggestion {
        CharacterAnimationSetupSuggestion(
            mouthFrames: mouthSuggestions(in: tree),
            eyeFrames: eyeSuggestions(in: tree)
        )
    }

    private static func mouthSuggestions(in tree: [TachieLayerNode]) -> [CharacterPartFrameSuggestion] {
        guard let root = categoryFolder(.mouth, in: tree) else { return [] }
        let leaves = leafNodes(in: root.children)

        // This five-step family is a genuine closed-to-open progression used by several
        // layered character packs, and is smoother than treating every phoneme as a step.
        let smoothNames = ["んー", "んへー", "んあー", "ほあ", "ほあー"]
        let smooth = smoothNames.compactMap { named($0, in: leaves) }
        if smooth.count == smoothNames.count {
            return smooth.enumerated().map {
                CharacterPartFrameSuggestion(
                    name: frameName(index: $0.offset, count: smooth.count),
                    sourceLayerIDs: [$0.element.id]
                )
            }
        }

        let groups = [
            ["通常", "口閉", "閉じ口", "閉", "closed", "close", "neutral", "rest", "んー", "むー"],
            ["口小", "小", "半開き", "small", "half", "んへー", "ほー"],
            ["口中", "中", "medium", "んあー", "ほあ"],
            ["口開", "開き口", "開", "open", "wide", "ほあー", "わあー", "あ"]
        ]
        let selected = groups.compactMap { firstNamed($0, in: leaves) }.uniquedByID()
        guard selected.count >= 2 else { return [] }
        return selected.enumerated().map {
            CharacterPartFrameSuggestion(
                name: frameName(index: $0.offset, count: selected.count),
                sourceLayerIDs: [$0.element.id]
            )
        }
    }

    private static func eyeSuggestions(in tree: [TachieLayerNode]) -> [CharacterPartFrameSuggestion] {
        guard let root = categoryFolder(.eye, in: tree) else { return [] }
        let leaves = leafNodes(in: root.children)
        var result: [CharacterPartFrameSuggestion] = []

        if let set = firstFolder(named: ["目セット", "eye set", "eyeset"], in: root.children) {
            let setLeaves = leafNodes(in: set.children)
            let white = firstNamed(["普通白目", "白目", "sclera", "eye white"], in: setLeaves)
                ?? setLeaves.first(where: { cleaned($0.name).contains("白目") })
            let pupilFolder = firstFolder(named: ["黒目", "瞳", "iris", "pupil"], in: set.children)
            let pupilLeaves = pupilFolder.map { leafNodes(in: $0.children) } ?? setLeaves
            let pupil = firstNamed(["普通目", "通常", "正面", "カメラ目線", "iris", "pupil"], in: pupilLeaves)
                ?? pupilLeaves.first(where: \.isVisible)
            if let white, let pupil {
                // The static white is drawn first and the iris is drawn over it.
                result.append(CharacterPartFrameSuggestion(
                    name: "開", sourceLayerIDs: [white.id, pupil.id]
                ))
            } else {
                result.append(CharacterPartFrameSuggestion(name: "開", sourceLayerIDs: [set.id]))
            }
        } else if let open = firstNamed(
            ["開き目", "目開き", "開", "open", "通常目", "普通目", "通常"], in: leaves
        ) {
            result.append(CharacterPartFrameSuggestion(name: "開", sourceLayerIDs: [open.id]))
        }

        if let middle = firstNamed(["細め目", "半目", "中間", "half", "half closed"], in: leaves) {
            result.append(CharacterPartFrameSuggestion(name: "中間", sourceLayerIDs: [middle.id]))
        }
        if let closed = firstNamed(
            ["目閉じ", "閉じ目", "閉", "closed", "にっこり", "なごみ目", "UU"], in: leaves
        ) {
            result.append(CharacterPartFrameSuggestion(name: "閉", sourceLayerIDs: [closed.id]))
        }

        let unique = result.uniquedBySources()
        return unique.count >= 2 ? unique : []
    }

    private static func categoryFolder(
        _ part: CharacterPartKind, in nodes: [TachieLayerNode]
    ) -> TachieLayerNode? {
        let names = part == .mouth ? ["口", "mouth"] : ["目", "eye", "eyes"]
        for node in nodes {
            if node.isFolder, names.contains(cleaned(node.name)) { return node }
            if let found = categoryFolder(part, in: node.children) { return found }
        }
        return nil
    }

    private static func leafNodes(in nodes: [TachieLayerNode]) -> [TachieLayerNode] {
        nodes.flatMap { $0.isFolder ? leafNodes(in: $0.children) : [$0] }
    }

    private static func firstFolder(
        named names: [String], in nodes: [TachieLayerNode]
    ) -> TachieLayerNode? {
        for node in nodes {
            if node.isFolder, names.contains(cleaned(node.name)) { return node }
            if let found = firstFolder(named: names, in: node.children) { return found }
        }
        return nil
    }

    private static func named(
        _ name: String, in nodes: [TachieLayerNode]
    ) -> TachieLayerNode? {
        nodes.first { cleaned($0.name) == name.lowercased() }
    }

    private static func firstNamed(
        _ names: [String], in nodes: [TachieLayerNode]
    ) -> TachieLayerNode? {
        for name in names {
            if let node = named(name, in: nodes) { return node }
        }
        return nil
    }

    private static func cleaned(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: "!*#@ \t"))
            .lowercased()
    }

    private static func frameName(index: Int, count: Int) -> String {
        if index == 0 { return "通常" }
        if index == count - 1 { return "開" }
        return "中間\(index)"
    }
}

private extension Array where Element == TachieLayerNode {
    func uniquedByID() -> [TachieLayerNode] {
        var seen: Set<UUID> = []
        return filter { seen.insert($0.id).inserted }
    }
}

private extension Array where Element == CharacterPartFrameSuggestion {
    func uniquedBySources() -> [CharacterPartFrameSuggestion] {
        var seen: Set<[UUID]> = []
        return filter { seen.insert($0.sourceLayerIDs).inserted }
    }
}
