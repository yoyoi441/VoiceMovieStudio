import Foundation

public struct StoryboardPlacement: Codable, Hashable, Sendable {
    public var position = CodablePoint(x: 0, y: 0.2)
    public var scale: Double = 1
    public var flipHorizontal = false
    public var isVisible = true
    public init() {}
}

public struct StoryboardAudio: Codable, Hashable, Sendable {
    public var data: AudioClipData
    public var mouthKeyframes: [MouthKeyframe]
    public init(data: AudioClipData, mouthKeyframes: [MouthKeyframe]) {
        self.data = data
        self.mouthKeyframes = mouthKeyframes
    }
}

public struct StoryboardCard: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var speakerID: UUID?
    public var dialogue: String
    public var durationFrames: Int
    /// Nil/zero is a cut for legacy projects; new cards can opt into easing in the inspector.
    public var transitionFrames: Int? = nil
    /// Missing entry means "inherit the last explicit placement for this character".
    public var placements: [UUID: StoryboardPlacement] = [:]
    public var audio: StoryboardAudio?
    public var subtitleID = UUID()
    public var audioID = UUID()
    public var characterClipIDs: [UUID: UUID] = [:]

    public init(speakerID: UUID?, dialogue: String, durationFrames: Int = 90) {
        self.speakerID = speakerID
        self.dialogue = dialogue
        self.durationFrames = durationFrames
    }

    public func duplicated() -> StoryboardCard {
        var copy = self
        copy.id = UUID()
        copy.subtitleID = UUID()
        copy.audioID = UUID()
        copy.characterClipIDs = [:]
        return copy
    }
}

public struct ResolvedStoryboardCard: Sendable {
    public var card: StoryboardCard
    public var startFrame: Int
    public var placements: [UUID: StoryboardPlacement]
}

public struct Storyboard: Codable, Hashable, Sendable {
    public var cards: [StoryboardCard] = []
    public var startFrame: Int
    /// Stable timebase: changing project output FPS does not shorten the dialogue.
    public var frameRate: Double
    public var initialPlacements: [UUID: StoryboardPlacement] = [:]
    public var trackIDs: [UUID] = []
    public var lastGenerated: [Clip] = []
    public var lastClipTracks: [UUID: UUID] = [:]

    public init(startFrame: Int = 0, frameRate: Double = 30) {
        self.startFrame = max(0, startFrame)
        self.frameRate = frameRate.isFinite && (1...240).contains(frameRate) ? frameRate : 30
    }

    public func resolved(characters: [Character]) throws -> [ResolvedStoryboardCard] {
        guard cards.count <= 300, frameRate.isFinite, (1...240).contains(frameRate), startFrame >= 0,
              startFrame <= Int(frameRate * 3600 * 24) else { throw StoryboardError.invalid }
        let known = Set(characters.map(\.id))
        var placements: [UUID: StoryboardPlacement] = [:]
        var cursor = startFrame
        var result: [ResolvedStoryboardCard] = []
        for card in cards {
            guard (1...Int(frameRate * 600)).contains(card.durationFrames),
                  (0...Int(frameRate * 600)).contains(card.transitionFrames ?? 0),
                  card.dialogue.count <= 10000 else { throw StoryboardError.invalid }
            if let speaker = card.speakerID {
                guard known.contains(speaker) else { throw StoryboardError.missingCharacter }
                if placements[speaker] == nil {
                    var value = initialPlacements[speaker] ?? StoryboardPlacement()
                    if initialPlacements[speaker] == nil {
                        value.flipHorizontal = characters.first { $0.id == speaker }?.defaultFlipHorizontal ?? false
                    }
                    placements[speaker] = value
                }
            }
            for (id, value) in card.placements where known.contains(id) {
                guard value.position.x.isFinite, value.position.y.isFinite, value.scale.isFinite,
                      (-2...2).contains(value.position.x), (-2...2).contains(value.position.y),
                      (0.05...5).contains(value.scale) else { throw StoryboardError.invalid }
                placements[id] = value
            }
            result.append(ResolvedStoryboardCard(card: card, startFrame: cursor, placements: placements))
            cursor += card.durationFrames
        }
        return result
    }

    public func hasTimelineChanges(_ timeline: Timeline) -> Bool {
        let owned = Set(lastGenerated.map(\.id))
        let actual = timeline.tracks.flatMap(\.clips).filter { owned.contains($0.id) }
        guard actual.count == lastGenerated.count else { return true }
        for expected in lastGenerated {
            guard actual.contains(expected),
                  let track = timeline.tracks.first(where: { $0.clips.contains(where: { $0.id == expected.id }) }),
                  lastClipTracks[expected.id] == track.id else { return true }
        }
        return false
    }

    /// Replaces only owned clips. Validation runs on values before the caller commits an Undo step.
    public mutating func rebuild(timeline: Timeline, characters: [Character], force: Bool = false) throws -> Timeline {
        if !force && hasTimelineChanges(timeline) { throw StoryboardError.timelineChanged }
        let owned = Set(lastGenerated.map(\.id))
        for track in timeline.tracks {
            for clip in track.clips where owned.contains(clip.id) {
                guard !track.isLocked, !clip.isLocked else { throw StoryboardError.locked }
            }
        }
        let resolved = try resolved(characters: characters)
        var generated: [Clip] = []
        var cast: [UUID] = []
        var channel: [UUID: Int] = [:]
        for (index, resolvedCard) in resolved.enumerated() {
            let start = Double(resolvedCard.startFrame) / frameRate
            let duration = Double(resolvedCard.card.durationFrames) / frameRate
            for id in characters.map(\.id) where resolvedCard.placements[id] != nil && !cast.contains(id) {
                cast.append(id)
            }
            for (slot, id) in cast.enumerated() {
                guard let placement = resolvedCard.placements[id], placement.isVisible else { continue }
                let clipID = cards[index].characterClipIDs[id] ?? UUID()
                cards[index].characterClipIDs[id] = clipID
                let speaking = cards[index].speakerID == id
                var clip = Clip(id: clipID, startTime: start, duration: duration, content: .character(
                    CharacterClipData(characterID: id,
                        linkedAudioClipID: speaking && cards[index].audio != nil ? cards[index].audioID : nil,
                        position: placement.position, scale: placement.scale,
                        mouthKeyframes: speaking ? cards[index].audio?.mouthKeyframes ?? [] : [])))
                clip.effects.flipHorizontal = placement.flipHorizontal
                if index > 0, let previous = resolved[index - 1].placements[id],
                   previous.isVisible, let frames = cards[index].transitionFrames, frames > 0,
                   previous.position != placement.position || previous.scale != placement.scale,
                   case .character(var data) = clip.content {
                    data.motion = CharacterMotion(fromPosition: previous.position, fromScale: previous.scale,
                        duration: Double(min(frames, cards[index].durationFrames)) / frameRate)
                    clip.content = .character(data)
                }
                generated.append(clip)
                channel[clip.id] = slot
            }
            let subtitle = Clip(id: cards[index].subtitleID, startTime: start, duration: duration,
                                content: .text(TextClipData(text: cards[index].dialogue)))
            generated.append(subtitle)
            if let audio = cards[index].audio {
                var data = audio.data
                data.linkedSubtitleClipID = subtitle.id
                generated.append(Clip(id: cards[index].audioID, startTime: start, duration: duration, content: .audio(data)))
            }
        }
        // Assign text and audio above all character channels, including characters introduced later.
        let subtitleIDs = Set(cards.map(\.subtitleID))
        for clip in generated {
            if subtitleIDs.contains(clip.id) { channel[clip.id] = cast.count }
            else if case .audio = clip.content { channel[clip.id] = cast.count + 1 }
        }
        var result = timeline
        for t in result.tracks.indices { result.tracks[t].clips.removeAll { owned.contains($0.id) } }
        for slot in 0..<(cast.count + 2) where !generated.isEmpty {
            if slot < trackIDs.count, result.tracks.contains(where: { $0.id == trackIDs[slot] }) { continue }
            let available = result.tracks.first { $0.clips.isEmpty && !$0.isLocked && $0.isVisible && !trackIDs.contains($0.id) }
            let id: UUID
            if let available { id = available.id }
            else {
                let track = Track(name: "レイヤー\(result.tracks.count + 1)")
                result.tracks.append(track)
                id = track.id
            }
            if slot < trackIDs.count { trackIDs[slot] = id } else { trackIDs.append(id) }
        }
        var clipTracks: [UUID: UUID] = [:]
        for clip in generated {
            guard let slot = channel[clip.id],
                  let t = result.tracks.firstIndex(where: { $0.id == trackIDs[slot] }) else { throw StoryboardError.invalid }
            guard !result.tracks[t].isLocked else { throw StoryboardError.locked }
            if result.tracks[t].clips.contains(where: { $0.startTime < clip.endTime - 0.0000001 && $0.endTime > clip.startTime + 0.0000001 }) {
                throw StoryboardError.occupied
            }
            result.tracks[t].clips.append(clip)
            clipTracks[clip.id] = result.tracks[t].id
        }
        lastGenerated = generated
        lastClipTracks = clipTracks
        return result
    }
}

public enum StoryboardError: Error, LocalizedError {
    case invalid, missingCharacter, timelineChanged, locked, occupied, scriptLine(Int)
    public var errorDescription: String? {
        switch self {
        case .invalid: "コマの長さ・配置が範囲外です。最大300コマ、1コマ10分までです。"
        case .missingCharacter: "コマの話者が見つかりません。話者を選び直してください。"
        case .timelineChanged: "絵コンテ由来の項目がタイムラインで変更されています。上書きするか確認してください。"
        case .locked: "絵コンテ由来の項目または配置先レイヤーがロックされています。"
        case .occupied: "配置先に別の項目があります。既存の編集は変更しませんでした。"
        case .scriptLine(let line): "台本の\(line)行目の話者が未登録・重複、または台詞が空です。「話者名：台詞」を確認してください。"
        }
    }
}

public enum StoryboardScript {
    public static func parse(_ text: String, characters: [Character], defaultSpeaker: UUID?,
                             durationFrames: Int) throws -> [StoryboardCard] {
        guard text.count <= 100000 else { throw StoryboardError.invalid }
        var result: [StoryboardCard] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var speaker = defaultSpeaker
            var dialogue = line
            if let separator = line.firstIndex(where: { $0 == "：" || $0 == ":" }) {
                let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                let matches = characters.filter { $0.name == name }
                guard matches.count == 1 else { throw StoryboardError.scriptLine(index + 1) }
                speaker = matches[0].id
                dialogue = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            }
            guard !dialogue.isEmpty else { throw StoryboardError.scriptLine(index + 1) }
            result.append(StoryboardCard(speakerID: speaker, dialogue: dialogue, durationFrames: durationFrames))
        }
        guard result.count <= 300 else { throw StoryboardError.invalid }
        return result
    }
}
