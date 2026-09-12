import Foundation

public enum MediaAssetKind: String, Codable, Hashable, Sendable {
    case video
    case audio
    case image
}

/// A project-owned source file. `fileName` is relative to the package's Assets folder,
/// while `originalName` is what the user sees in the material browser.
public struct MediaAsset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: MediaAssetKind
    public var fileName: String
    public var originalName: String
    public var duration: TimeInterval
    public var thumbnailFileName: String?
    public var credit: CreditMetadata

    public init(
        id: UUID = UUID(),
        kind: MediaAssetKind,
        fileName: String,
        originalName: String,
        duration: TimeInterval = 0,
        thumbnailFileName: String? = nil,
        credit: CreditMetadata = CreditMetadata()
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.originalName = originalName
        self.duration = duration
        self.thumbnailFileName = thumbnailFileName
        self.credit = credit
    }

    private enum CodingKeys: String, CodingKey { case id, kind, fileName, originalName, duration, thumbnailFileName, credit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(MediaAssetKind.self, forKey: .kind)
        fileName = try c.decode(String.self, forKey: .fileName)
        originalName = try c.decode(String.self, forKey: .originalName)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        thumbnailFileName = try c.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        credit = try c.decodeIfPresent(CreditMetadata.self, forKey: .credit) ?? CreditMetadata(title: originalName)
    }
}

public enum ProjectChatRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
    case system
}

public struct ProjectChatMessage: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var role: ProjectChatRole
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), role: ProjectChatRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

/// Strict, provider-independent output of a chat director. The app validates every source
/// range before applying it, so an AI response can never reference files outside the
/// project or create negative/invalid timeline times.
public struct VideoEditPlan: Codable, Hashable, Sendable {
    public var title: String
    public var summary: String
    public var replaceTimeline: Bool
    public var segments: [VideoEditSegment]

    public init(title: String, summary: String, replaceTimeline: Bool = true, segments: [VideoEditSegment]) {
        self.title = title
        self.summary = summary
        self.replaceTimeline = replaceTimeline
        self.segments = segments
    }
}

public struct VideoEditSegment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var sourceStart: TimeInterval
    public var sourceDuration: TimeInterval
    public var timelineStart: TimeInterval
    public var caption: String?

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        sourceStart: TimeInterval,
        sourceDuration: TimeInterval,
        timelineStart: TimeInterval,
        caption: String? = nil
    ) {
        self.id = id
        self.assetID = assetID
        self.sourceStart = sourceStart
        self.sourceDuration = sourceDuration
        self.timelineStart = timelineStart
        self.caption = caption
    }
}
