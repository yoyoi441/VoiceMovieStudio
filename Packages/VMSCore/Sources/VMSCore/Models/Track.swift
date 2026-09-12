import Foundation

/// A timeline layer. A track is generic — it can hold any mix of
/// text/character/audio clips — and is user-renameable; it's not tied to one content type.
public struct Track: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isVisible: Bool
    public var isLocked: Bool
    public var clips: [Clip]

    public init(
        id: UUID = UUID(),
        name: String,
        isVisible: Bool = true,
        isLocked: Bool = false,
        clips: [Clip] = []
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.clips = clips
    }

    public var duration: TimeInterval {
        clips.map(\.endTime).max() ?? 0
    }

    public func clips(at time: TimeInterval) -> [Clip] {
        clips.filter { $0.contains(time: time) }
    }
}
