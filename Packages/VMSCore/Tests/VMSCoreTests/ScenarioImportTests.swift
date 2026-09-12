import Foundation
import Testing
@testable import VMSCore

@Test func scenarioTextImportResolvesKnownAndReportsUnknownSpeakers() throws {
    let first = Character(name: "キャラクターA", baseImageFileName: "a.png")
    let second = Character(name: "キャラクターB", baseImageFileName: "b.png")
    let lines = try ScenarioDocumentParser.parseText(
        "キャラクターA：こんにちは\n未登録：確認してください\n字幕だけ",
        characters: [first, second], defaultSpeaker: second.id
    )
    #expect(lines.count == 3)
    #expect(lines[0].speakerID == first.id)
    #expect(!lines[0].needsSpeakerResolution)
    #expect(lines[1].speakerID == nil)
    #expect(lines[1].unresolvedSpeakerName == "未登録")
    #expect(lines[2].speakerID == second.id)
}

@Test func scenarioCSVImportSupportsQuotedDialogueAndDuration() throws {
    let character = Character(name: "話者A", baseImageFileName: "a.png")
    let data = Data("話者,セリフ,秒\n話者A,\"こんにちは、世界\",2.5\n".utf8)
    let lines = try ScenarioDocumentParser.parse(
        data: data, format: .csv, characters: [character], defaultSpeaker: nil
    )
    #expect(lines.count == 1)
    #expect(lines[0].speakerID == character.id)
    #expect(lines[0].dialogue == "こんにちは、世界")
    #expect(lines[0].durationSeconds == 2.5)
}

@Test func scenarioJSONImportAndPlacementCreateStoryboardCard() throws {
    let character = Character(name: "話者A", baseImageFileName: "a.png")
    let data = Data(#"{"lines":[{"speaker":"話者A","dialogue":"テスト","duration":4}]}"#.utf8)
    var line = try #require(ScenarioDocumentParser.parse(
        data: data, format: .json, characters: [character], defaultSpeaker: nil
    ).first)
    line.placement = .right
    let card = line.storyboardCard(frameRate: 30)
    #expect(card.durationFrames == 120)
    #expect(card.speakerID == character.id)
    #expect(card.placements[character.id]?.position == CodablePoint(x: 0.8, y: 0.88))
    #expect(card.placements[character.id]?.scale == 1.4)
}

@Test func scenarioAIPlanRoundTripsInJobStatus() throws {
    let plan = ScenarioAIPlan(summary: "交互に配置", suggestions: [
        ScenarioAIPlanSuggestion(lineIndex: 0, speakerName: "話者A", durationSeconds: 2.8, placement: .left, reason: "最初の話者")
    ])
    let status = RemoteAIJobStatus(id: UUID(), state: .completed, storyboardPlan: plan)
    let restored = try JSONDecoder().decode(RemoteAIJobStatus.self, from: JSONEncoder().encode(status))
    #expect(restored.storyboardPlan == plan)
}
