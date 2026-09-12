import Foundation
import VMSCore

extension ProjectStore {
    var storyboard: Storyboard? { currentScene.storyboard }

    func newStoryboard() -> Storyboard {
        let fps = project.frameRate.isFinite && (1...240).contains(project.frameRate) ? project.frameRate : 30
        let time = playhead.isFinite ? min(86400, max(0, playhead)) : 0
        var board = Storyboard(startFrame: Int((time * fps).rounded()), frameRate: fps)
        let prior = currentTimeline.tracks.filter(\.isVisible).flatMap(\.clips)
            .filter { $0.startTime <= time }.sorted { $0.startTime > $1.startTime }
        for clip in prior {
            guard case .character(let data) = clip.content, board.initialPlacements[data.characterID] == nil else { continue }
            var placement = StoryboardPlacement()
            let displayed = data.presentation(at: time - clip.startTime)
            placement.position = displayed.position
            placement.scale = min(5, max(0.05, displayed.scale * clip.effects.scale))
            placement.flipHorizontal = clip.effects.flipHorizontal
            board.initialPlacements[data.characterID] = placement
        }
        return board
    }

    @discardableResult
    func changeStoryboard(undo: Bool = true, force: Bool = false,
                          _ change: (inout Storyboard) throws -> Void) -> Bool {
        guard let index = project.scenes.firstIndex(where: { $0.id == currentScene.id }) else { return false }
        var board = storyboard ?? newStoryboard()
        do {
            try change(&board)
            let timeline = try board.rebuild(timeline: currentTimeline, characters: project.characters, force: force)
            if undo { beginUndoableChange() }
            isPlaying = false
            project.scenes[index].storyboard = board
            project.scenes[index].timeline = timeline
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func editStoryboardCard(_ id: UUID, undo: Bool = true, _ change: (inout StoryboardCard) -> Void) {
        changeStoryboard(undo: undo) { board in
            guard let index = board.cards.firstIndex(where: { $0.id == id }) else { return }
            let original = board.cards[index]
            change(&board.cards[index])
            if original.dialogue != board.cards[index].dialogue || original.speakerID != board.cards[index].speakerID {
                board.cards[index].audio = nil
            }
        }
    }
}
