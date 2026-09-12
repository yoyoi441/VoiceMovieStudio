import Foundation
import Testing
@testable import VMSCore

@Test func storyboardInheritsPerCharacterUntilNextExplicitPlacement() throws {
    let a = Character(name: "A", baseImageFileName: "a.png")
    let b = Character(name: "B", baseImageFileName: "b.png")
    var board = Storyboard()
    var first = StoryboardCard(speakerID: a.id, dialogue: "1")
    var left = StoryboardPlacement()
    left.position.x = -0.7
    first.placements[a.id] = left
    var second = StoryboardCard(speakerID: b.id, dialogue: "2")
    var right = StoryboardPlacement()
    right.position.x = 0.7
    second.placements[b.id] = right
    let third = StoryboardCard(speakerID: a.id, dialogue: "3")
    var fourth = StoryboardCard(speakerID: a.id, dialogue: "4")
    var center = StoryboardPlacement()
    center.position.x = 0
    fourth.placements[a.id] = center
    board.cards = [first, second, third, fourth]
    let resolved = try board.resolved(characters: [a, b])
    #expect(resolved[1].placements[a.id]?.position.x == -0.7)
    #expect(resolved[2].placements[b.id]?.position.x == 0.7)
    board.cards[0].placements[a.id]?.position.x = -0.5
    let changed = try board.resolved(characters: [a, b])
    #expect(changed[2].placements[a.id]?.position.x == -0.5)
    #expect(changed[3].placements[a.id]?.position.x == 0)
    #expect(changed[3].startFrame == 270)
}

@Test func storyboardRebuildPreservesOtherClipsAndStableIDs() throws {
    let character = Character(name: "A", baseImageFileName: "a.png")
    let unrelated = Clip(startTime: 0, duration: 30, content: .text(TextClipData(text: "既存素材")))
    var board = Storyboard()
    board.cards = [
        StoryboardCard(speakerID: character.id, dialogue: "1", durationFrames: 1),
        StoryboardCard(speakerID: character.id, dialogue: "2", durationFrames: 1),
        StoryboardCard(speakerID: character.id, dialogue: "3", durationFrames: 1)
    ]
    let before = Timeline(tracks: [Track(name: "既存", clips: [unrelated])])
    let first = try board.rebuild(timeline: before, characters: [character])
    let ids = board.lastGenerated.map(\.id)
    board.cards[1].dialogue = "変更"
    let second = try board.rebuild(timeline: first, characters: [character])
    #expect(second.tracks.flatMap(\.clips).contains(unrelated))
    #expect(board.lastGenerated.map(\.id) == ids)
    #expect(!board.hasTimelineChanges(second))
    var edited = second
    let t = try #require(edited.tracks.firstIndex { $0.clips.contains { $0.id == ids[0] } })
    edited.tracks[t].clips[0].startTime = 10
    #expect(board.hasTimelineChanges(edited))
    #expect(throws: StoryboardError.self) { try board.rebuild(timeline: edited, characters: [character]) }
    let forced = try board.rebuild(timeline: edited, characters: [character], force: true)
    #expect(!board.hasTimelineChanges(forced))
    var locked = forced
    locked.tracks[t].isLocked = true
    #expect(throws: StoryboardError.self) { try board.rebuild(timeline: locked, characters: [character], force: true) }
}

@Test func storyboardDeleteAndDuplicateHaveIndependentClipIDs() throws {
    let character = Character(name: "A", baseImageFileName: "a.png")
    var board = Storyboard()
    let original = StoryboardCard(speakerID: character.id, dialogue: "1")
    board.cards = [original, original.duplicated()]
    #expect(board.cards[0].id != board.cards[1].id)
    #expect(board.cards[0].subtitleID != board.cards[1].subtitleID)
    let first = try board.rebuild(timeline: Timeline(), characters: [character])
    let removedID = board.cards[0].subtitleID
    board.cards.removeFirst()
    let after = try board.rebuild(timeline: first, characters: [character])
    #expect(!after.tracks.flatMap(\.clips).contains { $0.id == removedID })
    #expect(board.lastGenerated.allSatisfy { $0.startTime == 0 })
}

@Test func storyboardScriptRejectsUnknownAndAmbiguousSpeakers() throws {
    let a = Character(name: "A", baseImageFileName: "a.png")
    let parsed = try StoryboardScript.parse("A：こんにちは\n\n続き", characters: [a], defaultSpeaker: a.id, durationFrames: 90)
    #expect(parsed.count == 2)
    #expect(parsed.allSatisfy { $0.speakerID == a.id })
    #expect(throws: StoryboardError.self) {
        try StoryboardScript.parse("B：未知", characters: [a], defaultSpeaker: a.id, durationFrames: 90)
    }
    #expect(throws: StoryboardError.self) {
        try StoryboardScript.parse("A：曖昧", characters: [a, a], defaultSpeaker: nil, durationFrames: 90)
    }
}

@Test func storyboardRoundTripsInsideProjectAndOldSceneStillLoads() throws {
    var scene = Scene(name: "メイン")
    var board = Storyboard()
    board.cards = [StoryboardCard(speakerID: nil, dialogue: "字幕")]
    scene.timeline = try board.rebuild(timeline: scene.timeline, characters: [])
    scene.storyboard = board
    let project = Project(name: "絵コンテ", scenes: [scene])
    let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
    #expect(restored == project)
    var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(scene)) as! [String: Any]
    old.removeValue(forKey: "storyboard")
    let legacy = try JSONDecoder().decode(Scene.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(legacy.storyboard == nil)
}

@Test func storyboardRejectsInvalidDurationWithoutChangingInputTimeline() {
    var board = Storyboard()
    board.cards = [StoryboardCard(speakerID: nil, dialogue: "字幕", durationFrames: 0)]
    let timeline = Timeline(tracks: Timeline.defaultLayerStack())
    #expect(throws: StoryboardError.self) { try board.rebuild(timeline: timeline, characters: []) }
    #expect(timeline.tracks.allSatisfy { $0.clips.isEmpty })
}
