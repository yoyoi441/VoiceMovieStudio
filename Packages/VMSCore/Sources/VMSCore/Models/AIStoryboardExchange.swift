import Foundation

/// A deliberately narrow, versioned exchange format for AI-assisted storyboard editing.
/// It contains labels and stable IDs, never project-owned file paths or binary material.
public struct AIStoryboardExchangeDocument: Codable, Hashable, Sendable {
    public static let currentFormat = "voice-movie-studio-ai-storyboard"
    public static let currentSchemaVersion = 1

    public var format: String
    public var schemaVersion: Int
    public var exportedAt: Date
    public var source: AIStoryboardSource
    public var characters: [AIStoryboardCharacter]
    public var assets: [AIStoryboardAsset]
    /// Read-only reference snapshot. AI clients should edit only `proposal`.
    public var currentStoryboard: AIStoryboardProposal
    public var proposal: AIStoryboardProposal
    public var instructions: [String]

    public init(
        exportedAt: Date = Date(),
        source: AIStoryboardSource,
        characters: [AIStoryboardCharacter],
        assets: [AIStoryboardAsset],
        currentStoryboard: AIStoryboardProposal,
        proposal: AIStoryboardProposal,
        instructions: [String]
    ) {
        format = Self.currentFormat
        schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.source = source
        self.characters = characters
        self.assets = assets
        self.currentStoryboard = currentStoryboard
        self.proposal = proposal
        self.instructions = instructions
    }
}

public struct AIStoryboardSource: Codable, Hashable, Sendable {
    public var projectID: UUID
    public var sceneID: UUID
    public var sceneName: String
    public var frameRate: Double
    public var resolution: CodableSize
    public var startFrame: Int
    /// A deterministic change detector, not an authentication token.
    public var revision: String
}

public struct AIStoryboardCharacter: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var groupName: String
    public var defaultFlipHorizontal: Bool
    public var expressions: [AIStoryboardNamedOption]
    public var presets: [AIStoryboardNamedOption]
    public var voice: AIStoryboardVoiceSummary
}

public struct AIStoryboardNamedOption: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
}

public struct AIStoryboardVoiceSummary: Codable, Hashable, Sendable {
    public var provider: String
    public var library: String
    public var style: String
    public var isConfigured: Bool
}

public struct AIStoryboardAsset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: MediaAssetKind
    public var displayName: String
    public var durationSeconds: Double
}

public struct AIStoryboardProposal: Codable, Hashable, Sendable {
    public var cards: [AIStoryboardProposedCard]
    public init(cards: [AIStoryboardProposedCard] = []) { self.cards = cards }
}

public struct AIStoryboardProposedCard: Codable, Hashable, Sendable {
    /// Existing cards must keep this ID. New cards use nil.
    public var sourceCardID: UUID?
    public var speakerID: UUID?
    public var dialogue: String
    public var durationFrames: Int
    public var transitionFrames: Int?
    /// Omitted characters inherit their last explicit placement.
    public var placements: [AIStoryboardProposedPlacement]
    /// Optional AI explanation shown during review; it never reaches the timeline.
    public var note: String?

    public init(
        sourceCardID: UUID? = nil,
        speakerID: UUID?,
        dialogue: String,
        durationFrames: Int,
        transitionFrames: Int? = nil,
        placements: [AIStoryboardProposedPlacement] = [],
        note: String? = nil
    ) {
        self.sourceCardID = sourceCardID
        self.speakerID = speakerID
        self.dialogue = dialogue
        self.durationFrames = durationFrames
        self.transitionFrames = transitionFrames
        self.placements = placements
        self.note = note
    }
}

public struct AIStoryboardProposedPlacement: Codable, Hashable, Sendable {
    public var characterID: UUID
    public var x: Double
    public var y: Double
    public var scale: Double
    public var flipHorizontal: Bool
    public var isVisible: Bool
    /// Nil means the character's configured default expression.
    public var expressionID: UUID?

    public init(
        characterID: UUID,
        x: Double,
        y: Double,
        scale: Double,
        flipHorizontal: Bool,
        isVisible: Bool,
        expressionID: UUID? = nil
    ) {
        self.characterID = characterID
        self.x = x
        self.y = y
        self.scale = scale
        self.flipHorizontal = flipHorizontal
        self.isVisible = isVisible
        self.expressionID = expressionID
    }
}

public enum AIStoryboardDifferenceKind: String, Codable, Hashable, Sendable {
    case added
    case modified
    case removed
    case unchanged
}

public struct AIStoryboardDifference: Hashable, Sendable {
    public var kind: AIStoryboardDifferenceKind
    public var oldIndex: Int?
    public var newIndex: Int?
    public var before: StoryboardCard?
    public var after: StoryboardCard?
    public var note: String?
}

public struct AIStoryboardImportResult: Sendable {
    public var storyboard: Storyboard
    public var differences: [AIStoryboardDifference]
    public var warnings: [String]
    public var isSourceOutdated: Bool

    public var changedCount: Int {
        differences.filter { $0.kind != .unchanged }.count
    }
}

public enum AIStoryboardExchangeError: Error, LocalizedError, Equatable {
    case unsupportedFormat
    case unsupportedVersion(Int)
    case wrongProject
    case wrongScene
    case invalidSource
    case tooManyCards
    case duplicateSourceCard
    case unknownSourceCard
    case unknownCharacter
    case unknownExpression
    case duplicatePlacement
    case invalidCard(Int, String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "AI絵コンテJSONの形式ではありません。"
        case .unsupportedVersion(let version):
            "このAI絵コンテJSONのバージョン（\(version)）には対応していません。"
        case .wrongProject:
            "別のプロジェクトから書き出されたAI絵コンテJSONです。"
        case .wrongScene:
            "別のシーンから書き出されたAI絵コンテJSONです。"
        case .invalidSource:
            "書き出し元のFPS・解像度・開始位置が不正です。"
        case .tooManyCards:
            "コマ数が上限の300件を超えています。"
        case .duplicateSourceCard:
            "同じ元コマIDが複数回指定されています。"
        case .unknownSourceCard:
            "現在の絵コンテに存在しない元コマIDが指定されています。"
        case .unknownCharacter:
            "未登録のキャラクターIDが指定されています。"
        case .unknownExpression:
            "指定されたキャラクターに存在しない表情IDです。"
        case .duplicatePlacement:
            "同じコマで同じキャラクターの配置が重複しています。"
        case .invalidCard(let index, let reason):
            "\(index + 1)コマ目が不正です：\(reason)"
        }
    }
}

public enum AIStoryboardExchange {
    public static func makeDocument(project: Project, scene: Scene, exportedAt: Date = Date()) -> AIStoryboardExchangeDocument {
        let board = scene.storyboard ?? Storyboard(startFrame: 0, frameRate: project.frameRate)
        let snapshot = proposal(from: board)
        return AIStoryboardExchangeDocument(
            exportedAt: exportedAt,
            source: AIStoryboardSource(
                projectID: project.id,
                sceneID: scene.id,
                sceneName: scene.name,
                frameRate: board.frameRate,
                resolution: project.resolution,
                startFrame: board.startFrame,
                revision: revision(project: project, scene: scene)
            ),
            characters: project.characters.map { character in
                AIStoryboardCharacter(
                    id: character.id,
                    name: character.name,
                    groupName: character.groupName,
                    defaultFlipHorizontal: character.defaultFlipHorizontal,
                    expressions: character.expressions.map { .init(id: $0.id, name: $0.name) },
                    presets: character.presets.map { .init(id: $0.id, name: $0.name) },
                    voice: .init(
                        provider: character.voiceProvider,
                        library: character.voiceLibrary,
                        style: character.voiceStyle,
                        isConfigured: !character.voiceProvider.isEmpty &&
                            (!character.voiceLibrary.isEmpty || character.defaultSpeakerID != nil)
                    )
                )
            },
            assets: project.mediaAssets.map {
                .init(
                    id: $0.id,
                    kind: $0.kind,
                    displayName: URL(fileURLWithPath: $0.originalName).lastPathComponent,
                    durationSeconds: $0.duration.isFinite ? max(0, $0.duration) : 0
                )
            },
            currentStoryboard: snapshot,
            proposal: snapshot,
            instructions: [
                "proposalだけを編集し、format、schemaVersion、source、currentStoryboardは変更しないでください。",
                "既存コマはsourceCardIDを保持し、新規コマはsourceCardIDをnullにしてください。",
                "charactersにあるIDだけをspeakerID、characterID、expressionIDへ指定してください。",
                "placementsを省略したキャラクターは直前の明示配置を継承します。座標は画面中心がX=0、Y=0です。",
                "素材ファイル本体・ローカルパス・実行命令はこの形式では扱いません。"
            ]
        )
    }

    public static func validate(
        _ document: AIStoryboardExchangeDocument,
        project: Project,
        scene: Scene
    ) throws -> AIStoryboardImportResult {
        guard document.format == AIStoryboardExchangeDocument.currentFormat else {
            throw AIStoryboardExchangeError.unsupportedFormat
        }
        guard document.schemaVersion == AIStoryboardExchangeDocument.currentSchemaVersion else {
            throw AIStoryboardExchangeError.unsupportedVersion(document.schemaVersion)
        }
        guard document.source.projectID == project.id else { throw AIStoryboardExchangeError.wrongProject }
        guard document.source.sceneID == scene.id else { throw AIStoryboardExchangeError.wrongScene }
        guard document.source.frameRate.isFinite, (1...240).contains(document.source.frameRate),
              document.source.resolution.width.isFinite, document.source.resolution.height.isFinite,
              document.source.resolution.width > 0, document.source.resolution.height > 0,
              document.source.startFrame >= 0 else { throw AIStoryboardExchangeError.invalidSource }
        guard document.proposal.cards.count <= 300 else { throw AIStoryboardExchangeError.tooManyCards }

        let current = scene.storyboard ?? Storyboard(startFrame: 0, frameRate: project.frameRate)
        guard current.frameRate.isFinite, (1...240).contains(current.frameRate), current.startFrame >= 0,
              Set(current.cards.map(\.id)).count == current.cards.count,
              Set(project.characters.map(\.id)).count == project.characters.count else {
            throw AIStoryboardExchangeError.invalidSource
        }
        let currentByID = Dictionary(uniqueKeysWithValues: current.cards.map { ($0.id, $0) })
        let currentIndex = Dictionary(uniqueKeysWithValues: current.cards.enumerated().map { ($0.element.id, $0.offset) })
        let characters = Dictionary(uniqueKeysWithValues: project.characters.map { ($0.id, $0) })
        var referencedSourceIDs = Set<UUID>()
        var nextCards: [StoryboardCard] = []
        var differences: [AIStoryboardDifference] = []

        for (index, proposed) in document.proposal.cards.enumerated() {
            let dialogue = proposed.dialogue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dialogue.isEmpty else { throw AIStoryboardExchangeError.invalidCard(index, "台詞が空です") }
            guard proposed.dialogue.count <= 10_000 else { throw AIStoryboardExchangeError.invalidCard(index, "台詞が10,000文字を超えています") }
            guard (proposed.note?.count ?? 0) <= 2_000 else {
                throw AIStoryboardExchangeError.invalidCard(index, "AIメモが2,000文字を超えています")
            }
            guard (1...Int(current.frameRate * 600)).contains(proposed.durationFrames) else {
                throw AIStoryboardExchangeError.invalidCard(index, "長さは1フレーム以上10分以内にしてください")
            }
            let transition = proposed.transitionFrames ?? 0
            guard transition >= 0, transition <= proposed.durationFrames else {
                throw AIStoryboardExchangeError.invalidCard(index, "移動時間がコマの長さを超えています")
            }
            if let speakerID = proposed.speakerID, characters[speakerID] == nil {
                throw AIStoryboardExchangeError.unknownCharacter
            }

            var placements: [UUID: StoryboardPlacement] = [:]
            for proposedPlacement in proposed.placements {
                guard let character = characters[proposedPlacement.characterID] else {
                    throw AIStoryboardExchangeError.unknownCharacter
                }
                guard placements[proposedPlacement.characterID] == nil else {
                    throw AIStoryboardExchangeError.duplicatePlacement
                }
                guard proposedPlacement.x.isFinite, proposedPlacement.y.isFinite, proposedPlacement.scale.isFinite,
                      (-2...2).contains(proposedPlacement.x), (-2...2).contains(proposedPlacement.y),
                      (0.05...5).contains(proposedPlacement.scale) else {
                    throw AIStoryboardExchangeError.invalidCard(index, "配置はX/Y -2〜2、拡大率0.05〜5の範囲にしてください")
                }
                if let expressionID = proposedPlacement.expressionID,
                   !character.expressions.contains(where: { $0.id == expressionID }) {
                    throw AIStoryboardExchangeError.unknownExpression
                }
                var placement = StoryboardPlacement()
                placement.position = CodablePoint(x: proposedPlacement.x, y: proposedPlacement.y)
                placement.scale = proposedPlacement.scale
                placement.flipHorizontal = proposedPlacement.flipHorizontal
                placement.isVisible = proposedPlacement.isVisible
                placement.expressionID = proposedPlacement.expressionID
                placements[proposedPlacement.characterID] = placement
            }

            let oldCard: StoryboardCard?
            var nextCard: StoryboardCard
            if let sourceID = proposed.sourceCardID {
                guard referencedSourceIDs.insert(sourceID).inserted else {
                    throw AIStoryboardExchangeError.duplicateSourceCard
                }
                guard let existing = currentByID[sourceID] else {
                    throw AIStoryboardExchangeError.unknownSourceCard
                }
                oldCard = existing
                nextCard = existing
                if existing.dialogue != proposed.dialogue || existing.speakerID != proposed.speakerID {
                    nextCard.audio = nil
                }
            } else {
                oldCard = nil
                nextCard = StoryboardCard(speakerID: proposed.speakerID, dialogue: proposed.dialogue,
                                          durationFrames: proposed.durationFrames)
            }
            nextCard.speakerID = proposed.speakerID
            nextCard.dialogue = proposed.dialogue
            nextCard.durationFrames = proposed.durationFrames
            nextCard.transitionFrames = transition == 0 ? nil : transition
            nextCard.placements = placements
            nextCards.append(nextCard)
            let originalIndex = proposed.sourceCardID.flatMap { currentIndex[$0] }
            differences.append(.init(
                kind: oldCard == nil ? .added : (oldCard == nextCard && originalIndex == index ? .unchanged : .modified),
                oldIndex: originalIndex,
                newIndex: index,
                before: oldCard,
                after: nextCard,
                note: proposed.note
            ))
        }

        for (index, card) in current.cards.enumerated() where !referencedSourceIDs.contains(card.id) {
            differences.append(.init(kind: .removed, oldIndex: index, newIndex: nil, before: card, after: nil, note: nil))
        }

        var next = current
        next.cards = nextCards
        _ = try next.resolved(characters: project.characters)
        let outdated = document.source.revision != revision(project: project, scene: scene)
        var warnings: [String] = []
        if outdated {
            warnings.append("書き出し後にプロジェクトまたは絵コンテが変更されています。現在との差分を特に確認してください。")
        }
        let removed = differences.filter { $0.kind == .removed }.count
        if removed > 0 { warnings.append("現在の絵コンテから\(removed)コマが削除されます。") }
        let audioReset = differences.filter {
            guard $0.kind == .modified, $0.before?.audio != nil else { return false }
            return $0.before?.dialogue != $0.after?.dialogue || $0.before?.speakerID != $0.after?.speakerID
        }.count
        if audioReset > 0 { warnings.append("台詞または話者が変わる\(audioReset)コマの音声は未生成へ戻ります。") }
        return AIStoryboardImportResult(storyboard: next, differences: differences, warnings: warnings,
                                        isSourceOutdated: outdated)
    }

    public static func revision(project: Project, scene: Scene) -> String {
        struct RevisionEnvelope: Encodable {
            var projectID: UUID
            var sceneID: UUID
            var frameRate: Double
            var resolution: CodableSize
            var storyboard: Storyboard?
            var characters: [Character]
            var assets: [MediaAsset]
        }
        let envelope = RevisionEnvelope(projectID: project.id, sceneID: scene.id, frameRate: project.frameRate,
                                        resolution: project.resolution, storyboard: scene.storyboard,
                                        characters: project.characters, assets: project.mediaAssets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(envelope)) ?? Data()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func proposal(from storyboard: Storyboard) -> AIStoryboardProposal {
        AIStoryboardProposal(cards: storyboard.cards.map { card in
            AIStoryboardProposedCard(
                sourceCardID: card.id,
                speakerID: card.speakerID,
                dialogue: card.dialogue,
                durationFrames: card.durationFrames,
                transitionFrames: card.transitionFrames,
                placements: card.placements.sorted { $0.key.uuidString < $1.key.uuidString }.map { id, placement in
                    AIStoryboardProposedPlacement(
                        characterID: id,
                        x: placement.position.x,
                        y: placement.position.y,
                        scale: placement.scale,
                        flipHorizontal: placement.flipHorizontal,
                        isVisible: placement.isVisible,
                        expressionID: placement.expressionID
                    )
                }
            )
        })
    }
}
