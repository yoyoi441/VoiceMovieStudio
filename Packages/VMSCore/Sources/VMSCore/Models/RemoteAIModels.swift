import Foundation

public enum RemoteAICapability: String, Codable, Hashable, Sendable {
    case transcription
    case highlights
    case clipPlanning
    case vision
}

public struct RemoteAINodeInfo: Codable, Hashable, Sendable {
    public var name: String
    public var version: String
    public var capabilities: [RemoteAICapability]
    public var models: [String]
    public var processor: String
    public var memoryGB: Int

    public init(name: String, version: String, capabilities: [RemoteAICapability], models: [String] = [], processor: String = "", memoryGB: Int = 0) {
        self.name = name
        self.version = version
        self.capabilities = capabilities
        self.models = models
        self.processor = processor
        self.memoryGB = memoryGB
    }
}

public enum RemoteAIJobState: String, Codable, Hashable, Sendable {
    case queued, running, completed, failed, cancelled
}

public struct TranscriptSegment: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var speaker: String?
    public var confidence: Double?

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String, speaker: String? = nil, confidence: Double? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.confidence = confidence
    }
}

public struct HighlightCandidate: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var title: String
    public var reason: String
    public var score: Double
    public var isSelected: Bool

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, title: String, reason: String, score: Double, isSelected: Bool = true) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
        self.reason = reason
        self.score = score
        self.isSelected = isSelected
    }
}

public struct RemoteAIAnalysis: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var assetID: UUID
    public var createdAt: Date
    public var language: String
    public var transcript: [TranscriptSegment]
    public var highlights: [HighlightCandidate]
    public var summary: String

    public init(id: UUID = UUID(), assetID: UUID, createdAt: Date = Date(), language: String = "ja", transcript: [TranscriptSegment] = [], highlights: [HighlightCandidate] = [], summary: String = "") {
        self.id = id
        self.assetID = assetID
        self.createdAt = createdAt
        self.language = language
        self.transcript = transcript
        self.highlights = highlights
        self.summary = summary
    }
}

public struct RemoteAIJobStatus: Codable, Hashable, Sendable {
    public var id: UUID
    public var state: RemoteAIJobState
    public var progress: Double
    public var message: String
    public var transcript: [TranscriptSegment]?
    public var highlights: [HighlightCandidate]?
    public var summary: String?
    public var storyboardPlan: ScenarioAIPlan?
    public var error: String?

    public init(id: UUID, state: RemoteAIJobState, progress: Double = 0, message: String = "", transcript: [TranscriptSegment]? = nil, highlights: [HighlightCandidate]? = nil, summary: String? = nil, storyboardPlan: ScenarioAIPlan? = nil, error: String? = nil) {
        self.id = id
        self.state = state
        self.progress = progress
        self.message = message
        self.transcript = transcript
        self.highlights = highlights
        self.summary = summary
        self.storyboardPlan = storyboardPlan
        self.error = error
    }
}
