import Foundation
import Testing
@testable import VMSCore

@Test func characterMotionEasesClampsAndKeepsSplitPhase() {
    var data = CharacterClipData(characterID: UUID(), position: CodablePoint(x: 1, y: 1), scale: 3)
    data.motion = CharacterMotion(fromPosition: CodablePoint(x: -1, y: -1), fromScale: 1, duration: 2)
    #expect(data.presentation(at: -1).position.x == -1)
    #expect(data.presentation(at: 1).position.x == 0)
    #expect(data.presentation(at: 1).scale == 2)
    #expect(data.presentation(at: 3).position.x == 1)
    #expect(data.presentation(at: 0.5).position.x == -0.6875)
    let expected = data.presentation(at: 0.9)
    data.motion?.offset = 0.7
    #expect(abs(data.presentation(at: 0.2).position.x - expected.position.x) < 1e-12)
    data.motion?.duration = .nan
    #expect(data.presentation(at: 1).position == data.position)
}

@Test func storyboardMotionResolvesPerCharacterAndClampsShortCards() throws {
    let actor = Character(name: "A", baseImageFileName: "a.png")
    for fps in [24.0, 30, 60] {
        var board = Storyboard(frameRate: fps)
        let first = StoryboardCard(speakerID: actor.id, dialogue: "1")
        var second = StoryboardCard(speakerID: actor.id, dialogue: "2", durationFrames: 2)
        var target = StoryboardPlacement()
        target.position.x = 0.8
        target.scale = 2
        second.placements[actor.id] = target
        second.transitionFrames = 9
        board.cards = [first, second, StoryboardCard(speakerID: actor.id, dialogue: "3")]
        let timeline = try board.rebuild(timeline: Timeline(), characters: [actor])
        let actors = board.lastGenerated.compactMap { clip -> CharacterClipData? in
            if case .character(let data) = clip.content { return data }; return nil
        }
        #expect(actors[0].motion == nil)
        #expect(actors[1].motion?.duration == 2 / fps)
        #expect(actors[1].presentation(at: 1 / fps).position.x == 0.4)
        #expect(actors[1].presentation(at: 2 / fps).position == actors[2].position)
        #expect(actors[2].motion == nil)
        let copy = try JSONDecoder().decode(Storyboard.self, from: JSONEncoder().encode(board))
        #expect(copy == board)
        #expect(!copy.hasTimelineChanges(timeline))
        board.cards[0].placements[actor.id] = target
        board.cards[0].placements[actor.id]?.isVisible = false
        _ = try board.rebuild(timeline: timeline, characters: [actor])
        let appearing = board.lastGenerated.compactMap { clip -> CharacterClipData? in
            if case .character(let data) = clip.content { return data }; return nil
        }
        #expect(appearing.allSatisfy { $0.motion == nil })
    }
}

@Test func motionLegacyDecodeAndInvalidTransition() throws {
    let actor = Character(name: "A", baseImageFileName: "a.png")
    let data = CharacterClipData(characterID: actor.id)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
    json.removeValue(forKey: "motion")
    let legacy = try JSONDecoder().decode(CharacterClipData.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.motion == nil)
    #expect(legacy.presentation(at: 100) == data)
    var board = Storyboard()
    board.cards = [StoryboardCard(speakerID: actor.id, dialogue: "1")]
    var cardJSON = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(board.cards[0])) as? [String: Any])
    cardJSON.removeValue(forKey: "transitionFrames")
    let oldCard = try JSONDecoder().decode(StoryboardCard.self, from: JSONSerialization.data(withJSONObject: cardJSON))
    #expect(oldCard.transitionFrames == nil)
    board.cards[0].transitionFrames = -1
    #expect(throws: StoryboardError.self) { try board.rebuild(timeline: Timeline(), characters: [actor]) }
}
