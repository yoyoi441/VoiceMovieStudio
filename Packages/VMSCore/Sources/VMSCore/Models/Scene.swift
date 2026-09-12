import Foundation

/// One independently-editable timeline within a project (the "シーン" concept — most
/// projects have just "メイン", but a scene tab bar lets you add more, e.g. for an intro
/// or a separate segment, each with its own layer stack).
public struct Scene: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var timeline: Timeline
    public var storyboard: Storyboard? = nil

    public init(id: UUID = UUID(), name: String, timeline: Timeline = Timeline(tracks: Timeline.defaultLayerStack())) {
        self.id = id
        self.name = name
        self.timeline = timeline
    }
}
