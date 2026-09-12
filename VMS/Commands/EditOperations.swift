import Foundation
import VMSCore

/// The clip-level edit operations behind the toolbar's history/clipboard/timeline-edit
/// button group (§3-3): cut/copy/paste/split/duplicate/lock/select-all/delete/ripple-
/// delete/select-left/select-right. Kept as a `ProjectStore` extension (not a separate
/// service object) since every operation is "read selection, mutate current timeline,
/// update selection" — the same shape as the mutators already on `ProjectStore`.
extension ProjectStore {
    func selectClips(
        intersecting timeRange: ClosedRange<TimeInterval>,
        trackRange: ClosedRange<Int>,
        extending: Bool
    ) {
        let lowerTime = max(0, min(timeRange.lowerBound, timeRange.upperBound))
        let upperTime = max(lowerTime, max(timeRange.lowerBound, timeRange.upperBound))
        var found: Set<UUID> = []
        for (trackIndex, track) in currentTimeline.tracks.enumerated()
            where trackRange.contains(trackIndex) {
            for clip in track.clips
                where clip.startTime <= upperTime && clip.endTime >= lowerTime {
                found.insert(clip.id)
            }
        }
        selectedClipIDs = extending ? selectedClipIDs.union(found) : found
        selectionAnchorClipID = found.first
    }

    func bulkClipMatch(sourceCharacterID: UUID?, phrase: String) -> BulkClipMatch {
        BulkClipMatcher.matching(
            in: currentTimeline, sourceCharacterID: sourceCharacterID, phrase: phrase
        )
    }

    func selectBulkClipMatch(sourceCharacterID: UUID?, phrase: String) -> Int {
        let match = bulkClipMatch(sourceCharacterID: sourceCharacterID, phrase: phrase)
        selectedClipIDs = match.clipIDs
        selectionAnchorClipID = match.clipIDs.first
        return match.clipIDs.count
    }

    /// Replaces all matching character clips and optionally re-synthesizes their linked
    /// voice clips with the target character's saved voice defaults. The result is
    /// committed only after every synthesis succeeds, so the entire operation is one Undo.
    func bulkReplaceCharacter(
        sourceCharacterID: UUID?,
        phrase: String,
        targetCharacterID: UUID,
        regenerateVoice: Bool
    ) async -> String {
        guard let target = project.character(withID: targetCharacterID) else {
            return "置換先キャラクターが見つかりません。"
        }
        let match = bulkClipMatch(sourceCharacterID: sourceCharacterID, phrase: phrase)
        guard !match.clipIDs.isEmpty else { return "条件に一致する項目がありません。" }

        let lockedIDs = Set(currentTimeline.tracks.flatMap { track in
            track.clips.filter { track.isLocked || $0.isLocked }.map(\.id)
        })
        guard match.clipIDs.isDisjoint(with: lockedIDs) else {
            return "対象にロック中の項目があります。ロックを解除してから実行してください。"
        }
        if regenerateVoice {
            let canGenerate = if target.voiceProvider == "A.I.VOICE2" {
                !target.voiceLibrary.isEmpty
            } else {
                (target.voiceProvider.isEmpty || target.voiceProvider == "VOICEVOX")
                    && target.defaultSpeakerID != nil
            }
            guard canGenerate else {
                return "置換先にアプリ内で再生成できる話者を設定するか、音声再生成をオフにしてください。"
            }
        }

        let projectID = project.id
        let sceneID = currentSceneID
        let directory = assetsDirectory
        var timeline = currentTimeline
        var characterCount = 0
        var createdVoiceURLs: [URL] = []

        for trackIndex in timeline.tracks.indices {
            for clipIndex in timeline.tracks[trackIndex].clips.indices {
                guard match.characterClipIDs.contains(timeline.tracks[trackIndex].clips[clipIndex].id),
                      case .character(var data) = timeline.tracks[trackIndex].clips[clipIndex].content else { continue }
                data.characterID = targetCharacterID
                data.expressionID = nil
                timeline.tracks[trackIndex].clips[clipIndex].content = .character(data)
                characterCount += 1
            }
        }

        var voiceCount = 0
        var skippedVoiceCount = 0
        if regenerateVoice {
            let mouthSpeeds = Dictionary(
                uniqueKeysWithValues: project.characters.map { ($0.id, $0.defaultMouthSpeed) }
            )
            for audioID in match.audioClipIDs {
                guard let original = timeline.tracks.flatMap(\.clips).first(where: { $0.id == audioID }),
                      case .audio(let originalData) = original.content,
                      let sourceText = originalData.sourceText,
                      !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    skippedVoiceCount += 1
                    continue
                }
                do {
                    let speech: SynthesizedSpeech
                    let settings: VoiceSettings
                    let expectedProvider: String?
                    let amplitudeMouthKeyframes: [MouthKeyframe]?
                    if target.voiceProvider == "A.I.VOICE2" {
                        settings = target.defaultVoiceSettings.validatedForAIVoice2()
                        let exported = try await aiv2Automation.synthesize(.init(
                            text: sourceText, speakerName: target.voiceLibrary, settings: settings
                        ))
                        defer { exported.removeTemporaryFiles() }
                        let analysis = try ExternalVoiceImport.analyze(
                            url: exported.wavURL, mouthSpeed: target.defaultMouthSpeed
                        )
                        speech = SynthesizedSpeech(
                            audioData: try Data(contentsOf: exported.wavURL),
                            moraTimings: [], duration: analysis.duration
                        )
                        amplitudeMouthKeyframes = analysis.mouthKeyframes
                        expectedProvider = "A.I.VOICE2"
                    } else {
                        guard let speakerID = target.defaultSpeakerID else {
                            throw SpeechRegeneration.Failure.invalid
                        }
                        settings = target.defaultVoiceSettings.validatedForVoiceVox()
                        speech = try await voiceEngine.synthesize(
                            text: sourceText, speakerID: speakerID, settings: settings
                        )
                        amplitudeMouthKeyframes = nil
                        expectedProvider = nil
                    }
                    guard project.id == projectID, currentSceneID == sceneID,
                          assetsDirectory == directory else {
                        throw SpeechRegeneration.Failure.targetChanged
                    }

                    var configured = original
                    var configuredData = originalData
                    configuredData.voiceProvider = expectedProvider
                    configuredData.speakerID = target.voiceProvider == "A.I.VOICE2"
                        ? nil : target.defaultSpeakerID
                    configuredData.voiceLibrary = target.voiceLibrary
                    configuredData.voiceStyle = target.voiceStyle
                    configuredData.voiceSettings = settings
                    configuredData.licenseNotes = target.usageTerms
                    configured.content = .audio(configuredData)
                    for trackIndex in timeline.tracks.indices {
                        if let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == audioID }) {
                            timeline.tracks[trackIndex].clips[clipIndex] = configured
                        }
                    }

                    let fileName = "voice_\(UUID().uuidString).wav"
                    let fileURL = directory.appendingPathComponent(fileName)
                    try speech.audioData.write(to: fileURL, options: .atomic)
                    createdVoiceURLs.append(fileURL)
                    timeline = try SpeechRegeneration.replacing(
                        original: configured,
                        in: timeline,
                        speech: speech,
                        fileName: fileName,
                        mouthSpeeds: mouthSpeeds.merging(
                            [targetCharacterID: target.defaultMouthSpeed], uniquingKeysWith: { _, new in new }
                        ),
                        expectedProvider: expectedProvider,
                        amplitudeMouthKeyframes: amplitudeMouthKeyframes
                    )
                    voiceCount += 1
                } catch {
                    for url in createdVoiceURLs { try? FileManager.default.removeItem(at: url) }
                    return "音声の一括再生成に失敗しました：\(error.localizedDescription)"
                }
            }
        }

        guard project.id == projectID, currentSceneID == sceneID,
              assetsDirectory == directory else {
            for url in createdVoiceURLs { try? FileManager.default.removeItem(at: url) }
            return SpeechRegeneration.Failure.targetChanged.errorDescription ?? "編集中のプロジェクトが変更されました。"
        }
        guard timeline != currentTimeline else { return "変更対象がありません。" }
        beginUndoableChange()
        currentTimeline = timeline
        selectedClipIDs = match.clipIDs

        var result = "立ち絵\(characterCount)件を「\(target.name)」へ変更しました"
        if regenerateVoice {
            result += "。音声\(voiceCount)件を再生成しました"
            if skippedVoiceCount > 0 { result += "（元セリフなし\(skippedVoiceCount)件は変更なし）" }
        }
        return result + "。"
    }

    func deleteSelected() {
        guard selectedClips.contains(where: { !$0.isLocked }) else { return }
        beginUndoableChange()
        var timeline = currentTimeline
        for trackIndex in timeline.tracks.indices {
            timeline.tracks[trackIndex].clips.removeAll { selectedClipIDs.contains($0.id) && !$0.isLocked }
        }
        currentTimeline = timeline
        selectedClipIDs = []
    }

    /// Deletes the selection and shifts every later clip on the same track(s) left to
    /// close the resulting gap ("削除して左詰め").
    func rippleDeleteSelected() {
        guard selectedClips.contains(where: { !$0.isLocked }) else { return }
        beginUndoableChange()
        var timeline = currentTimeline
        for trackIndex in timeline.tracks.indices {
            let removed = timeline.tracks[trackIndex].clips
                .filter { selectedClipIDs.contains($0.id) && !$0.isLocked }
                .sorted { $0.startTime < $1.startTime }
            guard !removed.isEmpty else { continue }

            var clips = timeline.tracks[trackIndex].clips.filter { clip in
                !(selectedClipIDs.contains(clip.id) && !clip.isLocked)
            }
            for gap in removed {
                for index in clips.indices where clips[index].startTime >= gap.startTime {
                    clips[index].startTime = max(0, clips[index].startTime - gap.duration)
                }
            }
            timeline.tracks[trackIndex].clips = clips
        }
        currentTimeline = timeline
        selectedClipIDs = []
    }

    /// Duplicates every selected (unlocked) clip, placing each copy immediately after its
    /// original on the same track, and selects the new copies.
    func duplicateSelected() {
        guard selectedClips.contains(where: { !$0.isLocked }) else { return }
        beginUndoableChange()
        var timeline = currentTimeline
        var newSelection: Set<UUID> = []
        for trackIndex in timeline.tracks.indices {
            let toDuplicate = timeline.tracks[trackIndex].clips.filter { selectedClipIDs.contains($0.id) && !$0.isLocked }
            for original in toDuplicate {
                var copy = original
                copy.id = UUID()
                copy.startTime = original.startTime + original.duration
                timeline.tracks[trackIndex].clips.append(copy)
                newSelection.insert(copy.id)
            }
        }
        currentTimeline = timeline
        selectedClipIDs = newSelection
    }

    /// Toggles lock on the selection as a group: if any selected clip is currently
    /// unlocked, locks all of them; otherwise unlocks all of them.
    func toggleLockSelected() {
        guard !selectedClipIDs.isEmpty else { return }
        beginUndoableChange()
        let shouldLock = selectedClips.contains { !$0.isLocked }
        var timeline = currentTimeline
        for trackIndex in timeline.tracks.indices {
            for clipIndex in timeline.tracks[trackIndex].clips.indices
            where selectedClipIDs.contains(timeline.tracks[trackIndex].clips[clipIndex].id) {
                timeline.tracks[trackIndex].clips[clipIndex].isLocked = shouldLock
            }
        }
        currentTimeline = timeline
    }

    func copySelected() {
        let entries = currentTimeline.tracks.flatMap { track in
            track.clips.filter { selectedClipIDs.contains($0.id) }.map { ClipboardEntry(trackID: track.id, clip: $0) }
        }
        guard !entries.isEmpty else { return }
        clipboard = entries
    }

    func cutSelected() {
        guard selectedClips.contains(where: { !$0.isLocked }) else { return }
        copySelected()
        deleteSelected()
    }

    /// Pastes the clipboard back into the tracks it was copied from (if they still exist),
    /// shifted so its earliest clip lands at the current playhead.
    func pasteClipboard() {
        guard !clipboard.isEmpty else { return }
        beginUndoableChange()
        let earliestStart = clipboard.map(\.clip.startTime).min() ?? 0
        let offset = playhead - earliestStart
        var timeline = currentTimeline
        var newSelection: Set<UUID> = []
        for entry in clipboard {
            guard let trackIndex = timeline.tracks.firstIndex(where: { $0.id == entry.trackID }),
                  !timeline.tracks[trackIndex].isLocked else { continue }
            var newClip = entry.clip
            newClip.id = UUID()
            newClip.startTime = max(0, entry.clip.startTime + offset)
            newClip.isLocked = false
            timeline.tracks[trackIndex].clips.append(newClip)
            newSelection.insert(newClip.id)
        }
        currentTimeline = timeline
        selectedClipIDs = newSelection
    }

    /// Splits clips spanning the playhead into two ("再生位置で分割"). Acts on the
    /// selection when there is one, otherwise on whatever clip(s) sit under the playhead.
    func splitAtPlayhead() {
        let time = playhead
        let timeline = currentTimeline
        let targetIDs: Set<UUID> = selectedClipIDs.isEmpty
            ? Set(timeline.tracks.flatMap { $0.clips.filter { $0.contains(time: time) }.map(\.id) })
            : selectedClipIDs

        func isSplittable(_ clip: Clip) -> Bool {
            targetIDs.contains(clip.id) && !clip.isLocked && clip.contains(time: time) && time > clip.startTime
        }
        let hasSplittable = timeline.tracks.contains { track in
            !track.isLocked && track.clips.contains(where: isSplittable)
        }
        guard hasSplittable else { return }

        beginUndoableChange()
        var mutable = timeline
        for trackIndex in mutable.tracks.indices {
            guard !mutable.tracks[trackIndex].isLocked else { continue }
            var newClips: [Clip] = []
            for clip in mutable.tracks[trackIndex].clips {
                guard isSplittable(clip) else {
                    newClips.append(clip)
                    continue
                }
                var first = clip
                first.duration = time - clip.startTime
                var second = clip
                second.id = UUID()
                second.startTime = time
                second.duration = clip.endTime - time
                for i in second.effects.effectsList.indices {
                    second.effects.effectsList[i].timeOffset = (second.effects.effectsList[i].timeOffset ?? 0) + first.duration
                }
                if case .character(var data) = second.content {
                    data.motion?.offset += first.duration
                    let shape = data.mouthShape(at: first.duration)
                    data.mouthKeyframes = [MouthKeyframe(time: 0, shape: shape)] + data.mouthKeyframes
                        .filter { $0.time > first.duration }
                        .map { MouthKeyframe(time: $0.time - first.duration, shape: $0.shape) }
                    second.content = .character(data)
                }
                newClips.append(first)
                newClips.append(second)
            }
            mutable.tracks[trackIndex].clips = newClips
        }
        currentTimeline = mutable
    }

    func selectAllLeftOfPlayhead() {
        selectedClipIDs = Set(currentTimeline.tracks.flatMap { $0.clips.filter { $0.startTime < playhead }.map(\.id) })
    }

    func selectAllRightOfPlayhead() {
        selectedClipIDs = Set(currentTimeline.tracks.flatMap { $0.clips.filter { $0.startTime >= playhead }.map(\.id) })
    }
}
