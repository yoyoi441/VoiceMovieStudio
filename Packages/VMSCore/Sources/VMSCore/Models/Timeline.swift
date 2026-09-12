import Foundation

public struct Timeline: Codable, Hashable, Sendable {
    public var tracks: [Track]

    public init(tracks: [Track] = []) {
        self.tracks = tracks
    }

    public var duration: TimeInterval {
        tracks.map(\.duration).max() ?? 0
    }
}

public extension Timeline {
    /// Stable painter order. Front items win; opt-in Z values order within each group.
    func visibleClipsInDrawOrder(at time: TimeInterval) -> [Clip] {
        tracks.filter(\.isVisible).flatMap { $0.clips(at: time) }.enumerated().sorted { a, b in
            if a.element.effects.showInFront != b.element.effects.showInFront {
                return !a.element.effects.showInFront
            }
            let az = a.element.effects.useZOrder && a.element.effects.zPosition.isFinite ? a.element.effects.zPosition : 0
            let bz = b.element.effects.useZOrder && b.element.effects.zPosition.isFinite ? b.element.effects.zPosition : 0
            return az == bz ? a.offset < b.offset : az < bz
        }.map(\.element)
    }
    /// A stack of empty, renameable generic layers. Every clip kind can be placed on
    /// every layer; names never imply or restrict content type.
    static func defaultLayerStack(count: Int = 30) -> [Track] {
        (0..<count).map { Track(name: "レイヤー\($0 + 1)") }
    }
}
