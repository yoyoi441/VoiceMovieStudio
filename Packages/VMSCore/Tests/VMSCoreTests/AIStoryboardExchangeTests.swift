import Foundation
import Testing
@testable import VMSCore

private func aiExchangeFixture() -> (Project, Scene, Character, CharacterExpression) {
    let expression = CharacterExpression(name: "笑顔", imageFileName: "private-expression.png")
    var character = Character(
        name: "話者A",
        groupName: "出演者",
        baseImageFileName: "/private/material/body.png",
        expressions: [expression],
        importedRawJSON: "{\"privatePath\":\"/private/profile\"}",
        voiceProvider: "音声エンジン",
        voiceLibrary: "話者A"
    )
    character.presets = [CharacterPreset(name: "通常", baseImageFileName: "/private/preset.png",
        mouthImageFileNames: [:], eyeImageFileNames: [:], defaultExpressionID: expression.id, layerVisibility: [:])]
    var board = Storyboard(startFrame: 30, frameRate: 30)
    var first = StoryboardCard(speakerID: character.id, dialogue: "こんにちは", durationFrames: 90)
    var placement = StoryboardPlacement()
    placement.position = CodablePoint(x: 0.75, y: 0.2)
    placement.expressionID = expression.id
    first.placements[character.id] = placement
    board.cards = [first, StoryboardCard(speakerID: character.id, dialogue: "続きです", durationFrames: 60)]
    var scene = Scene(name: "メイン")
    scene.storyboard = board
    let asset = MediaAsset(kind: .video, fileName: "/private/material/movie.mov",
                           originalName: "/private/display/参考動画.mov", duration: 12)
    let project = Project(name: "テスト", frameRate: 30, scenes: [scene], characters: [character], mediaAssets: [asset])
    return (project, scene, character, expression)
}

@Test func aiStoryboardExportContainsMetadataButNeverMaterialPathsOrImportedProfiles() throws {
    let (project, scene, _, _) = aiExchangeFixture()
    let document = AIStoryboardExchange.makeDocument(project: project, scene: scene, exportedAt: Date(timeIntervalSince1970: 0))
    let data = try JSONEncoder().encode(document)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("参考動画.mov"))
    #expect(json.contains("話者A"))
    #expect(!json.contains("/private/material"))
    #expect(!json.contains("/private/display"))
    #expect(!json.contains("/private/profile"))
    #expect(!json.contains("private-expression.png"))
    #expect(!json.contains("privatePath"))
}

@Test func aiStoryboardUnchangedRoundTripPreservesCardsAndExpression() throws {
    let (project, scene, character, expression) = aiExchangeFixture()
    let document = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    let result = try AIStoryboardExchange.validate(document, project: project, scene: scene)
    #expect(result.changedCount == 0)
    #expect(result.storyboard.cards == scene.storyboard?.cards)
    #expect(result.storyboard.cards[0].placements[character.id]?.expressionID == expression.id)
    #expect(!result.isSourceOutdated)
}

@Test func aiStoryboardImportBuildsReviewDiffAndPreservesExistingStableIDs() throws {
    let (project, scene, character, _) = aiExchangeFixture()
    var document = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    let original = try #require(scene.storyboard?.cards.first)
    document.proposal.cards[0].dialogue = "変更後の台詞"
    document.proposal.cards.removeLast()
    document.proposal.cards.append(AIStoryboardProposedCard(
        speakerID: character.id,
        dialogue: "新しいコマ",
        durationFrames: 45,
        placements: [.init(characterID: character.id, x: -0.7, y: 0.1, scale: 1.2,
                           flipHorizontal: true, isVisible: true)]
    ))
    let result = try AIStoryboardExchange.validate(document, project: project, scene: scene)
    #expect(result.storyboard.cards.count == 2)
    #expect(result.storyboard.cards[0].id == original.id)
    #expect(result.storyboard.cards[0].subtitleID == original.subtitleID)
    #expect(result.storyboard.cards[0].dialogue == "変更後の台詞")
    #expect(result.differences.filter { $0.kind == .modified }.count == 1)
    #expect(result.differences.filter { $0.kind == .added }.count == 1)
    #expect(result.differences.filter { $0.kind == .removed }.count == 1)
    #expect(result.warnings.contains { $0.contains("削除") })
}

@Test func aiStoryboardImportRejectsUnknownIDsDuplicatesAndUnsafeValues() throws {
    let (project, scene, character, _) = aiExchangeFixture()
    var unknownSpeaker = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    unknownSpeaker.proposal.cards[0].speakerID = UUID()
    #expect(throws: AIStoryboardExchangeError.self) {
        try AIStoryboardExchange.validate(unknownSpeaker, project: project, scene: scene)
    }

    var duplicate = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    duplicate.proposal.cards.append(duplicate.proposal.cards[0])
    #expect(throws: AIStoryboardExchangeError.self) {
        try AIStoryboardExchange.validate(duplicate, project: project, scene: scene)
    }

    var invalidPlacement = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    invalidPlacement.proposal.cards[0].placements = [
        .init(characterID: character.id, x: .infinity, y: 0, scale: 1, flipHorizontal: false, isVisible: true)
    ]
    #expect(throws: AIStoryboardExchangeError.self) {
        try AIStoryboardExchange.validate(invalidPlacement, project: project, scene: scene)
    }

    var unknownExpression = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    unknownExpression.proposal.cards[0].placements[0].expressionID = UUID()
    #expect(throws: AIStoryboardExchangeError.self) {
        try AIStoryboardExchange.validate(unknownExpression, project: project, scene: scene)
    }

    var invalidScene = scene
    invalidScene.storyboard?.frameRate = 0
    let validDocument = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    #expect(throws: AIStoryboardExchangeError.self) {
        try AIStoryboardExchange.validate(validDocument, project: project, scene: invalidScene)
    }
}

@Test func aiStoryboardReorderingIsShownAsAChange() throws {
    let (project, scene, _, _) = aiExchangeFixture()
    var document = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    document.proposal.cards.swapAt(0, 1)
    let result = try AIStoryboardExchange.validate(document, project: project, scene: scene)
    #expect(result.changedCount == 2)
    #expect(result.differences.filter { $0.kind == .modified }.count == 2)
}

@Test func aiStoryboardImportMarksSourceOutdatedAfterProjectMetadataChanges() throws {
    let (project, scene, _, _) = aiExchangeFixture()
    let document = AIStoryboardExchange.makeDocument(project: project, scene: scene)
    var changedProject = project
    changedProject.characters[0].name = "変更された名前"
    let result = try AIStoryboardExchange.validate(document, project: changedProject, scene: scene)
    #expect(result.isSourceOutdated)
    #expect(result.warnings.contains { $0.contains("書き出し後") })
}

@Test func storyboardExpressionRebuildReachesCharacterClipAndLegacyPlacementStillDecodes() throws {
    let (project, scene, character, expression) = aiExchangeFixture()
    var board = try #require(scene.storyboard)
    let timeline = try board.rebuild(timeline: Timeline(), characters: project.characters)
    let characterClips = timeline.tracks.flatMap(\.clips).compactMap { clip -> CharacterClipData? in
        if case .character(let data) = clip.content { return data }
        return nil
    }
    #expect(characterClips.first { $0.characterID == character.id }?.expressionID == expression.id)

    let legacy = "{\"position\":{\"x\":0,\"y\":0.2},\"scale\":1,\"flipHorizontal\":false,\"isVisible\":true}".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(StoryboardPlacement.self, from: legacy)
    #expect(decoded.expressionID == nil)
}
