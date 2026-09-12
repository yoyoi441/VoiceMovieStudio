import Foundation

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var frameRate: Double
    public var resolution: CodableSize
    public var scenes: [Scene]
    public var characters: [Character]
    public var mediaAssets: [MediaAsset]
    public var chatMessages: [ProjectChatMessage]
    public var aiAnalyses: [RemoteAIAnalysis]

    public init(
        id: UUID = UUID(),
        name: String,
        frameRate: Double = 30,
        resolution: CodableSize = CodableSize(width: 1920, height: 1080),
        scenes: [Scene] = [Scene(name: "メイン")],
        characters: [Character] = [],
        mediaAssets: [MediaAsset] = [],
        chatMessages: [ProjectChatMessage] = [],
        aiAnalyses: [RemoteAIAnalysis] = []
    ) {
        self.id = id
        self.name = name
        self.frameRate = frameRate
        self.resolution = resolution
        self.scenes = scenes.isEmpty ? [Scene(name: "メイン")] : scenes
        self.characters = characters
        self.mediaAssets = mediaAssets
        self.chatMessages = chatMessages
        self.aiAnalyses = aiAnalyses
    }

    public func character(withID id: UUID) -> Character? {
        characters.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, frameRate, resolution, scenes, characters, mediaAssets, chatMessages, aiAnalyses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        frameRate = try container.decode(Double.self, forKey: .frameRate)
        resolution = try container.decode(CodableSize.self, forKey: .resolution)
        let decodedScenes = try container.decodeIfPresent([Scene].self, forKey: .scenes) ?? []
        scenes = decodedScenes.isEmpty ? [Scene(name: "メイン")] : decodedScenes
        characters = try container.decodeIfPresent([Character].self, forKey: .characters) ?? []
        mediaAssets = try container.decodeIfPresent([MediaAsset].self, forKey: .mediaAssets) ?? []
        chatMessages = try container.decodeIfPresent([ProjectChatMessage].self, forKey: .chatMessages) ?? []
        aiAnalyses = try container.decodeIfPresent([RemoteAIAnalysis].self, forKey: .aiAnalyses) ?? []
    }
}

public extension Project {
    /// A clean project. Character and media material is added explicitly by the user.
    static func demo() -> Project {
        Project(name: "無題のプロジェクト", scenes: [Scene(name: "メイン")])
    }
}
