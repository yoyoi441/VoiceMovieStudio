import AppKit
import Foundation
import Observation
import VMSCore

@Observable
@MainActor
final class ProjectStore {
    var project: Project
    /// Which `Scene` in `project.scenes` the timeline/preview/inspector currently operate
    /// on. Kept as an id (not an index) so it survives scene reordering.
    var currentSceneID: UUID
    /// Source of truth for selection. `selectedClipID` below is a single-selection
    /// convenience view onto this, kept so existing single-select call sites (preview drag
    /// handles, inspector) don't need to know about multi-select at all.
    var selectedClipIDs: Set<UUID> = []
    var selectedClipID: UUID? {
        get { selectedClipIDs.first }
        set { selectedClipIDs = newValue.map { [$0] } ?? [] }
    }
    var playhead: TimeInterval = 0
    var pixelsPerSecond: Double = 120
    /// Updated by `TimelineView`'s `GeometryReader` as the window resizes — the "fit to
    /// window" zoom command needs to know how much horizontal space is actually available.
    var timelineViewportWidth: Double = 800
    var isPlaying: Bool = false
    /// Toolbar toggles (§3-4). Snap and preview-direct-manipulation are read by the
    /// timeline/preview drag gestures once those are wired up (Step 6); clip-above-only
    /// is stored now so its button can show correct on/off state ahead of that.
    var isSnapEnabled = true
    var isPreviewDirectManipulationEnabled = true
    var isClipAboveOnlyEnabled = false
    var errorMessage: String?
    /// Sheet-presentation flags live here (rather than as local View @State) so menu bar
    /// commands — which have no view of their own — can trigger the same sheets the
    /// toolbar buttons do.
    var isShowingCharacterManager = false
    var isShowingExport = false
    var isShowingProjectSettings = false
    var isShowingCredits = false
    var materialImportMessage: String?
    var isShowingHelp = false
    var isShowingTutorial = false
    var isShowingRemoteAI = false
    var isShowingBulkEdit = false
    private var didProcessLaunchMaterials = false

    /// Where synthesized audio / imported images for this project are written. Points at
    /// a scratch folder under Application Support until the project is saved, after which
    /// it points at `<package>/Assets` so everything travels together as one unit.
    private(set) var assetsDirectory: URL
    /// Set once the project has been saved to (or opened from) a `.VMS` package.
    private(set) var currentPackageURL: URL?

    let voiceEngine: VoiceEngine = VoiceVoxClient()
    let aiv2Catalog = AIVoice2Catalog()
    let aiv2Automation = AIVoice2AutomationClient()
    let imageProvider: CharacterImageProvider
    let videoFrameProvider: VideoFrameProvider

    // MARK: - Undo/Redo
    //
    // A plain snapshot stack of the whole (value-type, Codable) `Project` rather than
    // AppKit's `UndoManager` — this app isn't a `DocumentGroup`/`NSDocument`, and a simple
    // "push before you mutate" stack is enough for a project this size. Callers control
    // granularity: `beginUndoableChange()` is meant to be called exactly once per logical
    // edit (once per discrete command, once at the *start* of a drag/slider gesture) —
    // never per intermediate mutation — so one gesture always collapses to one undo step.
    private var undoStack: [Project] = []
    private var redoStack: [Project] = []
    /// Not `private` because `EditOperations.swift` (a same-module `ProjectStore`
    /// extension in a different file) reads/writes it — Swift's `private` is scoped to
    /// the declaring file, not the whole type, so that would block it.
    var clipboard: [ClipboardEntry] = []

    struct ClipboardEntry {
        var trackID: UUID
        var clip: Clip
    }

    init(project: Project = .demo()) {
        self.project = project
        self.currentSceneID = project.scenes[0].id
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let scratchAssets = support
            .appendingPathComponent("VMS", isDirectory: true)
            .appendingPathComponent(project.id.uuidString, isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
        self.assetsDirectory = scratchAssets
        self.imageProvider = CharacterImageProvider(assetsDirectory: scratchAssets)
        self.videoFrameProvider = VideoFrameProvider(assetsDirectory: scratchAssets)
    }

    /// Automation-safe equivalent of dropping files into the editor. The option is
    /// intentionally explicit and processed once per app process:
    /// `--import-material /absolute/path/to/material.psd`
    func importLaunchMaterialsIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) async {
        guard !didProcessLaunchMaterials else { return }
        didProcessLaunchMaterials = true
        var urls: [URL] = []
        var index = 1
        while index < arguments.count {
            guard arguments[index] == "--import-material", index + 1 < arguments.count else {
                index += 1
                continue
            }
            let url = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) { urls.append(url) }
            else { errorMessage = "起動時に指定された素材が見つかりません：\(url.lastPathComponent)" }
            index += 2
        }
        guard !urls.isEmpty else { return }
        await DroppedMaterialImporter.importURLs(urls, into: self)
        isShowingCharacterManager = true
    }

    var documentDisplayName: String {
        currentPackageURL?.deletingPathExtension().lastPathComponent ?? project.name
    }

    func registerMediaAsset(_ asset: MediaAsset) {
        beginUndoableChange()
        project.mediaAssets.append(asset)
    }

    func appendChatMessage(role: ProjectChatRole, text: String) {
        project.chatMessages.append(ProjectChatMessage(role: role, text: text))
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Call once, immediately before starting a logically-single edit (a discrete command,
    /// or the first `onChanged`/`onEditingChanged` tick of a drag/slider gesture).
    func beginUndoableChange() {
        undoStack.append(project)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        project = previous
        sanitizeSelectionAndScene()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        project = next
        sanitizeSelectionAndScene()
    }

    private func sanitizeSelectionAndScene() {
        if !project.scenes.contains(where: { $0.id == currentSceneID }) {
            currentSceneID = project.scenes[0].id
        }
        let liveIDs = Set(currentTimeline.tracks.flatMap { $0.clips.map(\.id) })
        selectedClipIDs.formIntersection(liveIDs)
    }

    // MARK: - Current scene

    /// Index of `currentSceneID` in `project.scenes`, falling back to the first scene if
    /// the id doesn't (yet, or anymore) match — e.g. right after `open(from:)` swaps in a
    /// project whose scenes have different ids.
    private var currentSceneIndex: Int {
        project.scenes.firstIndex(where: { $0.id == currentSceneID }) ?? 0
    }

    var currentScene: Scene {
        project.scenes[currentSceneIndex]
    }

    var currentTimeline: Timeline {
        get { project.scenes[currentSceneIndex].timeline }
        set { project.scenes[currentSceneIndex].timeline = newValue }
    }

    func selectScene(id: UUID) {
        guard project.scenes.contains(where: { $0.id == id }) else { return }
        currentSceneID = id
        selectedClipIDs = []
        playhead = 0
        isPlaying = false
    }

    func addScene() {
        beginUndoableChange()
        let scene = Scene(name: "シーン\(project.scenes.count + 1)")
        project.scenes.append(scene)
        selectScene(id: scene.id)
    }

    func renameScene(id: UUID, to newName: String) {
        beginUndoableChange()
        guard let index = project.scenes.firstIndex(where: { $0.id == id }) else { return }
        project.scenes[index].name = newName
    }

    /// Closes a scene tab. A project must always keep at least one scene, so the last
    /// remaining one can't be closed.
    func removeScene(id: UUID) {
        guard project.scenes.count > 1 else { return }
        beginUndoableChange()
        let wasCurrent = id == currentSceneID
        project.scenes.removeAll { $0.id == id }
        if wasCurrent {
            selectScene(id: project.scenes[0].id)
        }
    }

    func moveScene(fromOffsets: IndexSet, toOffset: Int) {
        beginUndoableChange()
        project.scenes.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    // MARK: - Selection

    var selectedClip: Clip? {
        guard let id = selectedClipID else { return nil }
        return clip(withID: id)
    }

    /// All currently-selected clips, in track/time order (stable for display).
    var selectedClips: [Clip] {
        currentTimeline.tracks.flatMap { track in
            track.clips.filter { selectedClipIDs.contains($0.id) }
        }
    }

    func isSelected(_ clipID: UUID) -> Bool {
        selectedClipIDs.contains(clipID)
    }

    func toggleSelection(_ clipID: UUID) {
        if selectedClipIDs.contains(clipID) {
            selectedClipIDs.remove(clipID)
        } else {
            selectedClipIDs.insert(clipID)
        }
    }

    func selectAll() {
        selectedClipIDs = Set(currentTimeline.tracks.flatMap { $0.clips.map(\.id) })
    }

    func clearSelection() {
        selectedClipIDs = []
    }

    /// Anchor for ⇧-click range selection — the last clip selected with a plain click.
    var selectionAnchorClipID: UUID?

    /// Click-selection with modifier support (§6): plain click selects only this clip,
    /// ⌘-click toggles it into/out of the selection, ⇧-click selects every clip (across
    /// all tracks) whose start time falls between the anchor and this one.
    func selectClip(_ clipID: UUID, extend: Bool = false, range: Bool = false) {
        if range, let anchorID = selectionAnchorClipID ?? selectedClipIDs.first,
           let anchor = clip(withID: anchorID), let target = clip(withID: clipID) {
            let lower = min(anchor.startTime, target.startTime)
            let upper = max(anchor.startTime, target.startTime)
            selectedClipIDs = Set(
                currentTimeline.tracks.flatMap { $0.clips }
                    .filter { $0.startTime >= lower && $0.startTime <= upper }
                    .map(\.id)
            )
        } else if extend {
            toggleSelection(clipID)
            selectionAnchorClipID = clipID
        } else {
            selectedClipIDs = [clipID]
            selectionAnchorClipID = clipID
        }
    }

    /// Shifts every clip in `originalStartTimes` by `delta` from its captured original
    /// position — the multi-clip counterpart to `moveClip(id:to:)`, used while dragging a
    /// selection that contains more than one clip so they move as a group.
    func moveSelectedClips(originalStartTimes: [UUID: TimeInterval], delta: TimeInterval) {
        var timeline = currentTimeline
        for trackIndex in timeline.tracks.indices {
            guard !timeline.tracks[trackIndex].isLocked else { continue }
            for clipIndex in timeline.tracks[trackIndex].clips.indices {
                let id = timeline.tracks[trackIndex].clips[clipIndex].id
                guard let original = originalStartTimes[id], !timeline.tracks[trackIndex].clips[clipIndex].isLocked else { continue }
                timeline.tracks[trackIndex].clips[clipIndex].startTime = max(0, original + delta)
            }
        }
        currentTimeline = timeline
    }

    func track(containing clipID: UUID) -> Track? {
        currentTimeline.tracks.first { track in
            track.clips.contains { $0.id == clipID }
        }
    }

    // MARK: - Clip mutation (continuous — callers decide undo granularity)

    /// No-op if the clip (or its track) is locked — locked items can't be edited until
    /// unlocked again.
    func updateClip(_ clip: Clip) {
        guard !clip.isLocked else { return }
        var timeline = currentTimeline
        for trackIndex in timeline.tracks.indices {
            guard !timeline.tracks[trackIndex].isLocked else { continue }
            if let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clip.id }) {
                timeline.tracks[trackIndex].clips[clipIndex] = clip
                currentTimeline = timeline
                return
            }
        }
    }

    /// Moves an item's anchor in centre-origin normalized coordinates (-1...1).
    /// No-op for audio clips, which have no position.
    func setPosition(clipID: UUID, x: Double, y: Double) {
        guard var clip = clip(withID: clipID), !clip.isLocked else { return }
        let point = CodablePoint(x: min(max(x, -1), 1), y: min(max(y, -1), 1))
        switch clip.content {
        case .text(var data):
            data.position = point
            clip.content = .text(data)
        case .character(var data):
            data.position = point
            // A direct drag is a static placement edit, not a new motion keyframe.
            data.scale = data.presentation(at: playhead - clip.startTime).scale
            data.motion = nil
            clip.content = .character(data)
        case .image(var data):
            data.position = point
            clip.content = .image(data)
        case .video(var data):
            data.position = point
            clip.content = .video(data)
        case .audio:
            return
        }
        updateClip(clip)
    }

    private func clip(withID id: UUID) -> Clip? {
        for track in currentTimeline.tracks {
            if let clip = track.clips.first(where: { $0.id == id }) {
                return clip
            }
        }
        return nil
    }

    func moveClip(id: UUID, to newStartTime: TimeInterval) {
        var timeline = currentTimeline
        for trackIndex in timeline.tracks.indices {
            guard !timeline.tracks[trackIndex].isLocked else { continue }
            if let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                guard !timeline.tracks[trackIndex].clips[clipIndex].isLocked else { return }
                timeline.tracks[trackIndex].clips[clipIndex].startTime = max(0, newStartTime)
                currentTimeline = timeline
                return
            }
        }
    }

    /// Resizes a clip by moving one edge, keeping the other fixed. `minDuration` guards
    /// against dragging a handle past its opposite edge (or past zero length).
    func resizeClip(id: UUID, edge: ClipEdge, to newTime: TimeInterval, minDuration: TimeInterval = 0.1) {
        var timeline = currentTimeline
        for trackIndex in timeline.tracks.indices {
            guard !timeline.tracks[trackIndex].isLocked else { continue }
            guard let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) else { continue }
            var clip = timeline.tracks[trackIndex].clips[clipIndex]
            guard !clip.isLocked else { return }
            switch edge {
            case .leading:
                let maxStart = clip.startTime + clip.duration - minDuration
                let clampedStart = max(0, min(newTime, maxStart))
                for i in clip.effects.effectsList.indices {
                    clip.effects.effectsList[i].timeOffset = (clip.effects.effectsList[i].timeOffset ?? 0) + clampedStart - clip.startTime
                }
                if case .character(var data) = clip.content {
                    data.motion?.offset += clampedStart - clip.startTime
                    clip.content = .character(data)
                }
                clip.duration += clip.startTime - clampedStart
                clip.startTime = clampedStart
            case .trailing:
                let minEnd = clip.startTime + minDuration
                let clampedEnd = max(minEnd, newTime)
                clip.duration = clampedEnd - clip.startTime
            }
            timeline.tracks[trackIndex].clips[clipIndex] = clip
            currentTimeline = timeline
            return
        }
    }

    private func appendToFirstAvailableTrack(_ clip: Clip) {
        var timeline = currentTimeline
        let target = timeline.tracks.firstIndex { track in
            !track.isLocked && !track.clips.contains { $0.startTime < clip.endTime && $0.endTime > clip.startTime }
        }
        if let target {
            timeline.tracks[target].clips.append(clip)
        } else {
            timeline.tracks.append(Track(name: "レイヤー\(timeline.tracks.count + 1)", clips: [clip]))
        }
        currentTimeline = timeline
    }

    /// Places each generated clip on the first free generic track.
    func insert(_ result: TTSImportResult) {
        beginUndoableChange()
        appendToFirstAvailableTrack(result.audioClip)
        appendToFirstAvailableTrack(result.textClip)
        if let characterClip = result.characterClip {
            appendToFirstAvailableTrack(characterClip)
        }
    }

    /// Creates a clip at the playhead and drops it on the first unlocked track that's
    /// free at that time range, adding a new track if every existing one is occupied or
    /// locked. The generic path behind every "add item" toolbar command that doesn't need
    /// TTS's reserved-layer behavior. One undo step for the whole operation, including any
    /// track it had to create.
    @discardableResult
    func addClip(content: ClipContent, duration: TimeInterval, at startTime: TimeInterval? = nil, effects: ClipEffects = ClipEffects()) -> UUID {
        let startTime = startTime ?? playhead
        beginUndoableChange()
        var timeline = currentTimeline
        let range = startTime..<(startTime + duration)
        let trackIndex: Int
        if let index = timeline.tracks.firstIndex(where: { track in
            !track.isLocked && !track.clips.contains { $0.startTime < range.upperBound && $0.endTime > range.lowerBound }
        }) {
            trackIndex = index
        } else {
            timeline.tracks.append(Track(name: "レイヤー\(timeline.tracks.count + 1)"))
            trackIndex = timeline.tracks.count - 1
        }
        let clip = Clip(startTime: startTime, duration: duration, content: content, effects: effects)
        timeline.tracks[trackIndex].clips.append(clip)
        currentTimeline = timeline
        selectedClipIDs = [clip.id]
        return clip.id
    }

    // MARK: - Tracks

    func renameTrack(id: UUID, to newName: String) {
        beginUndoableChange()
        var timeline = currentTimeline
        guard let index = timeline.tracks.firstIndex(where: { $0.id == id }) else { return }
        timeline.tracks[index].name = newName
        currentTimeline = timeline
    }

    func addTrack() {
        beginUndoableChange()
        var timeline = currentTimeline
        timeline.tracks.append(Track(name: "レイヤー\(timeline.tracks.count + 1)"))
        currentTimeline = timeline
    }

    func removeTrack(id: UUID) {
        beginUndoableChange()
        var timeline = currentTimeline
        timeline.tracks.removeAll { $0.id == id }
        currentTimeline = timeline
        // Drop the selection if it pointed at a clip that lived on the removed track.
        sanitizeSelectionAndScene()
    }

    // MARK: - Characters

    func addCharacter(name: String, baseImageURL: URL) {
        do {
            let fileName = try AssetImporter.importFile(from: baseImageURL, into: assetsDirectory, prefix: "char")
            beginUndoableChange()
            project.characters.append(Character(name: name, baseImageFileName: fileName))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setMouthImage(for characterID: UUID, shape: MouthShape, sourceURL: URL) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        do {
            let fileName = try AssetImporter.importFile(from: sourceURL, into: assetsDirectory, prefix: "mouth")
            beginUndoableChange()
            let frameIndex = Character.mouthCompatibilityIndex(
                shape, frameCount: project.characters[index].mouthAnimationFrames.count)
            if project.characters[index].mouthAnimationFrames.indices.contains(frameIndex) {
                project.characters[index].mouthAnimationFrames[frameIndex].imageFileName = fileName
                project.characters[index].mouthAnimationFrames[frameIndex].sourceLayerID = nil
                project.characters[index].mouthAnimationFrames[frameIndex].sourceLayerIDs = nil
            }
            project.characters[index].synchronizeLegacyAnimationImages()
            try regeneratePSDAnimationBase(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEyeImage(for characterID: UUID, shape: EyeShape, sourceURL: URL) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        do {
            let fileName = try AssetImporter.importFile(from: sourceURL, into: assetsDirectory, prefix: "eye")
            beginUndoableChange()
            let frameIndex = Character.eyeCompatibilityIndex(
                shape, frameCount: project.characters[index].eyeAnimationFrames.count)
            if project.characters[index].eyeAnimationFrames.indices.contains(frameIndex) {
                project.characters[index].eyeAnimationFrames[frameIndex].imageFileName = fileName
                project.characters[index].eyeAnimationFrames[frameIndex].sourceLayerID = nil
                project.characters[index].eyeAnimationFrames[frameIndex].sourceLayerIDs = nil
            }
            project.characters[index].synchronizeLegacyAnimationImages()
            try regeneratePSDAnimationBase(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addCharacterPartFrame(characterID: UUID, part: CharacterPartKind) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        beginUndoableChange()
        switch part {
        case .mouth:
            let count = project.characters[index].mouthAnimationFrames.count
            let insertion = max(1, count - 1)
            let frame = CharacterPartFrame(name: "中間\(max(1, count - 2))")
            project.characters[index].mouthAnimationFrames.insert(frame, at: insertion)
        case .eye:
            let count = project.characters[index].eyeAnimationFrames.count
            let insertion = max(1, count - 1)
            let frame = CharacterPartFrame(name: "中間\(max(1, count - 1))")
            project.characters[index].eyeAnimationFrames.insert(frame, at: insertion)
        }
        project.characters[index].synchronizeLegacyAnimationImages()
        do { try regeneratePSDAnimationBase(at: index) }
        catch { errorMessage = error.localizedDescription }
    }

    func removeCharacterPartFrame(characterID: UUID, part: CharacterPartKind, frameID: UUID) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        let minimum = part == .mouth ? 3 : 2
        let currentCount = part == .mouth
            ? project.characters[index].mouthAnimationFrames.count
            : project.characters[index].eyeAnimationFrames.count
        guard currentCount > minimum else { return }
        beginUndoableChange()
        switch part {
        case .mouth:
            project.characters[index].mouthAnimationFrames.removeAll { $0.id == frameID }
        case .eye:
            project.characters[index].eyeAnimationFrames.removeAll { $0.id == frameID }
        }
        project.characters[index].synchronizeLegacyAnimationImages()
        do { try regeneratePSDAnimationBase(at: index) }
        catch { errorMessage = error.localizedDescription }
    }

    func setCharacterPartFrameImage(
        characterID: UUID,
        part: CharacterPartKind,
        frameID: UUID,
        sourceURL: URL
    ) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        do {
            let prefix = part == .mouth ? "mouth" : "eye"
            let fileName = try AssetImporter.importFile(from: sourceURL, into: assetsDirectory, prefix: prefix)
            beginUndoableChange()
            guard setCharacterPartFrame(
                at: index, part: part, frameID: frameID,
                imageFileName: fileName, sourceLayerID: nil
            ) else { return }
            project.characters[index].synchronizeLegacyAnimationImages()
            try regeneratePSDAnimationBase(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addExpression(for characterID: UUID, name: String, sourceURL: URL) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        do {
            let fileName = try AssetImporter.importFile(from: sourceURL, into: assetsDirectory, prefix: "expression")
            beginUndoableChange()
            project.characters[index].expressions.append(CharacterExpression(name: name, imageFileName: fileName))
        } catch { errorMessage = error.localizedDescription }
    }

    func replacePSD(for characterID: UUID, sourceURL: URL) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        do {
            let original = try AssetImporter.importFile(from: sourceURL, into: assetsDirectory, prefix: "character_source")
            let preview = try DroppedMaterialImporter.importPSDPreview(from: sourceURL, into: assetsDirectory)
            let layers = DroppedMaterialImporter.layerNodes(try PSDLayerExtractor.extract(from: sourceURL, into: assetsDirectory))
            beginUndoableChange()
            project.characters[index].tachieKind = .psd
            project.characters[index].importedSource = original
            project.characters[index].baseImageFileName = preview
            project.characters[index].layerTree = layers
            project.characters[index].animationBaseImageFileName = nil
            for frameIndex in project.characters[index].mouthAnimationFrames.indices {
                project.characters[index].mouthAnimationFrames[frameIndex].sourceLayerID = nil
                project.characters[index].mouthAnimationFrames[frameIndex].sourceLayerIDs = nil
                project.characters[index].mouthAnimationFrames[frameIndex].imageFileName = nil
            }
            for frameIndex in project.characters[index].eyeAnimationFrames.indices {
                project.characters[index].eyeAnimationFrames[frameIndex].sourceLayerID = nil
                project.characters[index].eyeAnimationFrames[frameIndex].sourceLayerIDs = nil
                project.characters[index].eyeAnimationFrames[frameIndex].imageFileName = nil
            }
            project.characters[index].synchronizeLegacyAnimationImages()
            imageProvider.invalidate(fileName: preview)
        } catch { errorMessage = error.localizedDescription }
    }

    func reloadPSDPreview(for characterID: UUID) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }),
              let source = project.characters[index].importedSource else { return }
        do {
            let preview = try DroppedMaterialImporter.importPSDPreview(
                from: assetsDirectory.appendingPathComponent(source), into: assetsDirectory
            )
            let layers = DroppedMaterialImporter.layerNodes(try PSDLayerExtractor.extract(
                from: assetsDirectory.appendingPathComponent(source), into: assetsDirectory
            ))
            beginUndoableChange()
            project.characters[index].baseImageFileName = preview
            project.characters[index].layerTree = layers
            project.characters[index].animationBaseImageFileName = nil
            for frameIndex in project.characters[index].mouthAnimationFrames.indices {
                project.characters[index].mouthAnimationFrames[frameIndex].sourceLayerID = nil
                project.characters[index].mouthAnimationFrames[frameIndex].sourceLayerIDs = nil
                project.characters[index].mouthAnimationFrames[frameIndex].imageFileName = nil
            }
            for frameIndex in project.characters[index].eyeAnimationFrames.indices {
                project.characters[index].eyeAnimationFrames[frameIndex].sourceLayerID = nil
                project.characters[index].eyeAnimationFrames[frameIndex].sourceLayerIDs = nil
                project.characters[index].eyeAnimationFrames[frameIndex].imageFileName = nil
            }
            project.characters[index].synchronizeLegacyAnimationImages()
            imageProvider.invalidate(fileName: preview)
        } catch { errorMessage = error.localizedDescription }
    }

    func setPSDLayerVisibility(characterID: UUID, layerID: UUID, isVisible: Bool) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        var tree = project.characters[index].layerTree
        guard updateLayer(layerID, in: &tree, { $0.isVisible = isVisible }) else { return }
        beginUndoableChange()
        project.characters[index].layerTree = tree
    }

    func movePSDLayer(characterID: UUID, layerID: UUID, direction: Int) {
        guard let characterIndex = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        var tree = project.characters[characterIndex].layerTree
        guard moveLayer(layerID, in: &tree, direction: direction, toEdge: nil) else { return }
        beginUndoableChange()
        project.characters[characterIndex].layerTree = tree
    }

    func movePSDLayerToEdge(characterID: UUID, layerID: UUID, toTop: Bool) {
        guard let characterIndex = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        var tree = project.characters[characterIndex].layerTree
        guard moveLayer(layerID, in: &tree, direction: 0, toEdge: toTop) else { return }
        beginUndoableChange()
        project.characters[characterIndex].layerTree = tree
    }

    func restorePSDLayerSourceOrder(characterID: UUID) {
        guard let characterIndex = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        var tree = project.characters[characterIndex].layerTree
        func restore(_ nodes: inout [TachieLayerNode]) {
            for index in nodes.indices { restore(&nodes[index].children) }
            let current = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
            nodes.sort { lhs, rhs in
                switch (lhs.sourceOrder, rhs.sourceOrder) {
                case let (l?, r?) where l != r: return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return (current[lhs.id] ?? 0) < (current[rhs.id] ?? 0)
                }
            }
        }
        restore(&tree)
        guard tree != project.characters[characterIndex].layerTree else { return }
        beginUndoableChange()
        project.characters[characterIndex].layerTree = tree
    }

    func createPSDLayerFolder(characterID: UUID, name: String, parentFolderID: UUID?) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let characterIndex = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        var tree = project.characters[characterIndex].layerTree
        let folder = TachieLayerNode(name: cleaned, isFolder: true)
        if let parentFolderID {
            guard updateLayer(parentFolderID, in: &tree, { $0.children.append(folder) }) else { return }
        } else {
            tree.append(folder)
        }
        beginUndoableChange()
        project.characters[characterIndex].layerTree = tree
    }

    func movePSDLayer(characterID: UUID, layerID: UUID, toFolderID: UUID?) {
        guard layerID != toFolderID,
              let characterIndex = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        var tree = project.characters[characterIndex].layerTree
        guard let moving = extractLayer(layerID, from: &tree) else { return }
        if let toFolderID {
            guard !containsLayer(toFolderID, in: moving.children),
                  updateLayer(toFolderID, in: &tree, { node in
                      if node.isFolder { node.children.append(moving) }
                  }),
                  findLayer(toFolderID, in: tree)?.isFolder == true else { return }
        } else {
            tree.append(moving)
        }
        beginUndoableChange()
        project.characters[characterIndex].layerTree = tree
    }

    func renameCharacter(id: UUID, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = project.characters.firstIndex(where: { $0.id == id }),
              project.characters[index].name != cleaned else { return }
        beginUndoableChange()
        project.characters[index].name = cleaned
    }

    func assignPSDLayer(characterID: UUID, layerID: UUID, mouthShape: MouthShape? = nil, eyeShape: EyeShape? = nil) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }),
              let layer = findLayer(layerID, in: project.characters[index].layerTree) else { return }
        do {
            let fileName = try animationImageFileName(for: layer)
            beginUndoableChange()
            if let mouthShape {
                let target = Character.mouthCompatibilityIndex(
                    mouthShape, frameCount: project.characters[index].mouthAnimationFrames.count)
                if project.characters[index].mouthAnimationFrames.indices.contains(target) {
                    project.characters[index].mouthAnimationFrames[target].imageFileName = fileName
                    project.characters[index].mouthAnimationFrames[target].sourceLayerID = layerID
                    project.characters[index].mouthAnimationFrames[target].sourceLayerIDs = [layerID]
                }
            }
            if let eyeShape {
                let target = Character.eyeCompatibilityIndex(
                    eyeShape, frameCount: project.characters[index].eyeAnimationFrames.count)
                if project.characters[index].eyeAnimationFrames.indices.contains(target) {
                    project.characters[index].eyeAnimationFrames[target].imageFileName = fileName
                    project.characters[index].eyeAnimationFrames[target].sourceLayerID = layerID
                    project.characters[index].eyeAnimationFrames[target].sourceLayerIDs = [layerID]
                }
            }
            project.characters[index].synchronizeLegacyAnimationImages()
            try regeneratePSDAnimationBase(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assignPSDLayer(
        characterID: UUID,
        layerID: UUID,
        part: CharacterPartKind,
        frameID: UUID
    ) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }),
              let layer = findLayer(layerID, in: project.characters[index].layerTree),
              characterPartFrameExists(at: index, part: part, frameID: frameID) else { return }
        do {
            let fileName = try animationImageFileName(for: layer)
            beginUndoableChange()
            guard setCharacterPartFrame(
                at: index, part: part, frameID: frameID,
                imageFileName: fileName, sourceLayerID: layerID,
                sourceLayerIDs: [layerID]
            ) else { return }
            project.characters[index].synchronizeLegacyAnimationImages()
            try regeneratePSDAnimationBase(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func characterPartFrameExists(at index: Int, part: CharacterPartKind, frameID: UUID) -> Bool {
        switch part {
        case .mouth: return project.characters[index].mouthAnimationFrames.contains { $0.id == frameID }
        case .eye: return project.characters[index].eyeAnimationFrames.contains { $0.id == frameID }
        }
    }

    /// A selectable PSD folder represents its currently visible child layers. Saving
    /// that subtree as one transparent full-canvas PNG lets compound eyes (white + iris,
    /// for example) occupy one animation frame without flattening the source PSD.
    private func animationImageFileName(for layer: TachieLayerNode) throws -> String {
        if let fileName = layer.imageFileName { return fileName }
        let visibleFiles = flattenedVisibleLayers(layer.children).reversed().compactMap(\.imageFileName)
        guard !visibleFiles.isEmpty else {
            throw NSError(
                domain: "VoiceMovieStudio.PSD", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "選択したPSDフォルダーに表示中の画像レイヤーがありません。"]
            )
        }
        return try writeCompositeImage(filesInDrawOrder: visibleFiles, prefix: "psd_part")
    }

    private func animationImageFileName(
        for layerIDs: [UUID], in tree: [TachieLayerNode]
    ) throws -> String {
        let layers = layerIDs.compactMap { findLayer($0, in: tree) }
        guard layers.count == layerIDs.count else {
            throw NSError(
                domain: "VoiceMovieStudio.PSD", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "自動設定に必要なPSDレイヤーが見つかりません。"]
            )
        }
        if layers.count == 1 { return try animationImageFileName(for: layers[0]) }
        let files = layers.flatMap { layer -> [String] in
            if let imageFileName = layer.imageFileName { return [imageFileName] }
            return flattenedVisibleLayers(layer.children).reversed().compactMap(\.imageFileName)
        }
        guard !files.isEmpty else {
            throw NSError(
                domain: "VoiceMovieStudio.PSD", code: 11,
                userInfo: [NSLocalizedDescriptionKey: "自動設定するPSDパーツの画像がありません。"]
            )
        }
        return try writeCompositeImage(filesInDrawOrder: files, prefix: "psd_part_set")
    }

    @discardableResult
    func configureRecommendedPSDAnimation(characterID: UUID) -> String {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else {
            return "キャラクターが見つかりません。"
        }
        let character = project.characters[index]
        guard character.tachieKind == .psd, !character.layerTree.isEmpty else {
            return "PSDレイヤーを読み込んでから実行してください。"
        }
        let suggestion = PSDCharacterAnimationDefaultDetector.detect(in: character.layerTree)
        guard !suggestion.mouthFrames.isEmpty || !suggestion.eyeFrames.isEmpty else {
            return "口または目の推奨パターンを判別できませんでした。手動で設定してください。"
        }

        do {
            let mouthFrames = try suggestion.mouthFrames.map { suggestion in
                CharacterPartFrame(
                    name: suggestion.name,
                    imageFileName: try animationImageFileName(
                        for: suggestion.sourceLayerIDs, in: character.layerTree
                    ),
                    sourceLayerID: suggestion.sourceLayerIDs.count == 1
                        ? suggestion.sourceLayerIDs[0] : nil,
                    sourceLayerIDs: suggestion.sourceLayerIDs
                )
            }
            let eyeFrames = try suggestion.eyeFrames.map { suggestion in
                CharacterPartFrame(
                    name: suggestion.name,
                    imageFileName: try animationImageFileName(
                        for: suggestion.sourceLayerIDs, in: character.layerTree
                    ),
                    sourceLayerID: suggestion.sourceLayerIDs.count == 1
                        ? suggestion.sourceLayerIDs[0] : nil,
                    sourceLayerIDs: suggestion.sourceLayerIDs
                )
            }

            beginUndoableChange()
            if !mouthFrames.isEmpty {
                project.characters[index].mouthAnimationFrames = mouthFrames
            }
            if !eyeFrames.isEmpty {
                project.characters[index].eyeAnimationFrames = eyeFrames
                project.characters[index].blinkEnabled = true
            }
            project.characters[index].synchronizeLegacyAnimationImages()
            try regeneratePSDAnimationBase(at: index)

            let mouthResult = mouthFrames.isEmpty ? "口は未判定" : "口パク\(mouthFrames.count)枚"
            let eyeResult = eyeFrames.isEmpty ? "目は未判定" : "目パチ\(eyeFrames.count)枚"
            return "おすすめ設定を適用しました（\(mouthResult)・\(eyeResult)）。"
        } catch {
            errorMessage = error.localizedDescription
            return "自動設定に失敗しました：\(error.localizedDescription)"
        }
    }

    private func regeneratePSDAnimationBase(at characterIndex: Int) throws {
        guard project.characters.indices.contains(characterIndex),
              project.characters[characterIndex].tachieKind == .psd else { return }
        let exclusions = CharacterPartLayerResolver.exclusionLayerIDs(for: project.characters[characterIndex])
        guard !exclusions.isEmpty else {
            project.characters[characterIndex].animationBaseImageFileName = nil
            return
        }
        let files = flattenedVisibleLayers(
            project.characters[characterIndex].layerTree,
            excluding: exclusions
        ).reversed().compactMap(\.imageFileName)
        guard !files.isEmpty else {
            throw NSError(
                domain: "VoiceMovieStudio.PSD", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "口・目を除外したPSD基準画像を作成できませんでした。"]
            )
        }
        let fileName = try writeCompositeImage(filesInDrawOrder: files, prefix: "psd_animation_base")
        project.characters[characterIndex].animationBaseImageFileName = fileName
        if let defaultID = project.characters[characterIndex].defaultExpressionID,
           let expressionIndex = project.characters[characterIndex].expressions.firstIndex(where: { $0.id == defaultID }) {
            project.characters[characterIndex].expressions[expressionIndex].animationBaseImageFileName = fileName
        }
    }

    private func writeCompositeImage(filesInDrawOrder: [String], prefix: String) throws -> String {
        guard let firstName = filesInDrawOrder.first,
              let first = imageProvider.image(named: firstName) else {
            throw NSError(
                domain: "VoiceMovieStudio.PSD", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "PSD合成に使用する画像レイヤーを読み込めませんでした。"]
            )
        }
        let image = NSImage(size: first.size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        for file in filesInDrawOrder {
            imageProvider.image(named: file)?.draw(
                in: NSRect(origin: .zero, size: first.size), from: .zero,
                operation: .sourceOver, fraction: 1
            )
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "VoiceMovieStudio.PSD", code: 9,
                userInfo: [NSLocalizedDescriptionKey: "PSDレイヤーの合成画像を作成できませんでした。"]
            )
        }
        let fileName = "\(prefix)_\(UUID().uuidString).png"
        try png.write(to: assetsDirectory.appendingPathComponent(fileName), options: .atomic)
        imageProvider.invalidate(fileName: fileName)
        return fileName
    }

    private func setCharacterPartFrame(
        at characterIndex: Int,
        part: CharacterPartKind,
        frameID: UUID,
        imageFileName: String,
        sourceLayerID: UUID?,
        sourceLayerIDs: [UUID]? = nil
    ) -> Bool {
        switch part {
        case .mouth:
            guard let frameIndex = project.characters[characterIndex].mouthAnimationFrames.firstIndex(where: { $0.id == frameID }) else { return false }
            project.characters[characterIndex].mouthAnimationFrames[frameIndex].imageFileName = imageFileName
            project.characters[characterIndex].mouthAnimationFrames[frameIndex].sourceLayerID = sourceLayerID
            project.characters[characterIndex].mouthAnimationFrames[frameIndex].sourceLayerIDs = sourceLayerIDs
        case .eye:
            guard let frameIndex = project.characters[characterIndex].eyeAnimationFrames.firstIndex(where: { $0.id == frameID }) else { return false }
            project.characters[characterIndex].eyeAnimationFrames[frameIndex].imageFileName = imageFileName
            project.characters[characterIndex].eyeAnimationFrames[frameIndex].sourceLayerID = sourceLayerID
            project.characters[characterIndex].eyeAnimationFrames[frameIndex].sourceLayerIDs = sourceLayerIDs
        }
        return true
    }

    func savePSDComposite(characterID: UUID, expressionName: String?, setAsDefault: Bool = false) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        do {
            let visibleFiles = flattenedVisibleLayers(project.characters[index].layerTree).reversed().compactMap(\.imageFileName)
            guard !visibleFiles.isEmpty else {
                throw NSError(domain: "VoiceMovieStudio.PSD", code: 3, userInfo: [NSLocalizedDescriptionKey: "表示中の画像レイヤーがありません。"]) }
            let fileName = try writeCompositeImage(filesInDrawOrder: visibleFiles, prefix: "psd_composite")
            let exclusions = CharacterPartLayerResolver.exclusionLayerIDs(for: project.characters[index])
            let animationFileName: String?
            if exclusions.isEmpty {
                animationFileName = nil
            } else {
                let neutralFiles = flattenedVisibleLayers(
                    project.characters[index].layerTree, excluding: exclusions
                ).reversed().compactMap(\.imageFileName)
                animationFileName = try writeCompositeImage(
                    filesInDrawOrder: neutralFiles, prefix: "psd_expression_base"
                )
            }
            beginUndoableChange()
            if let expressionName, !expressionName.trimmingCharacters(in: .whitespaces).isEmpty {
                let expression = CharacterExpression(
                    name: expressionName, imageFileName: fileName,
                    animationBaseImageFileName: animationFileName
                )
                project.characters[index].expressions.append(expression)
                if setAsDefault { project.characters[index].defaultExpressionID = expression.id }
            } else {
                project.characters[index].baseImageFileName = fileName
                project.characters[index].animationBaseImageFileName = animationFileName
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func findLayer(_ id: UUID, in nodes: [TachieLayerNode]) -> TachieLayerNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findLayer(id, in: node.children) { return found }
        }
        return nil
    }

    private func updateLayer(_ id: UUID, in nodes: inout [TachieLayerNode], _ change: (inout TachieLayerNode) -> Void) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id { change(&nodes[index]); return true }
            if updateLayer(id, in: &nodes[index].children, change) { return true }
        }
        return false
    }

    private func moveLayer(_ id: UUID, in nodes: inout [TachieLayerNode], direction: Int, toEdge: Bool?) -> Bool {
        if let source = nodes.firstIndex(where: { $0.id == id }) {
            let destination = toEdge.map { $0 ? 0 : nodes.count - 1 } ?? source + direction
            guard nodes.indices.contains(destination), source != destination else { return false }
            let node = nodes.remove(at: source)
            nodes.insert(node, at: destination)
            return true
        }
        for index in nodes.indices where moveLayer(id, in: &nodes[index].children, direction: direction, toEdge: toEdge) { return true }
        return false
    }

    private func extractLayer(_ id: UUID, from nodes: inout [TachieLayerNode]) -> TachieLayerNode? {
        if let index = nodes.firstIndex(where: { $0.id == id }) { return nodes.remove(at: index) }
        for index in nodes.indices {
            if let result = extractLayer(id, from: &nodes[index].children) { return result }
        }
        return nil
    }

    private func containsLayer(_ id: UUID, in nodes: [TachieLayerNode]) -> Bool {
        nodes.contains { $0.id == id || containsLayer(id, in: $0.children) }
    }

    private func flattenedVisibleLayers(
        _ nodes: [TachieLayerNode],
        parentVisible: Bool = true,
        excluding excludedIDs: Set<UUID> = []
    ) -> [TachieLayerNode] {
        nodes.flatMap { node -> [TachieLayerNode] in
            guard !excludedIDs.contains(node.id) else { return [] }
            let visible = parentVisible && node.isVisible
            if node.isFolder {
                return flattenedVisibleLayers(
                    node.children, parentVisible: visible, excluding: excludedIDs
                )
            }
            return visible ? [node] : []
        }
    }

    func removeExpression(for characterID: UUID, expressionID: UUID) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        beginUndoableChange()
        project.characters[index].expressions.removeAll { $0.id == expressionID }
        if project.characters[index].defaultExpressionID == expressionID {
            project.characters[index].defaultExpressionID = nil
        }
        for sceneIndex in project.scenes.indices {
            for trackIndex in project.scenes[sceneIndex].timeline.tracks.indices {
                for clipIndex in project.scenes[sceneIndex].timeline.tracks[trackIndex].clips.indices {
                    guard case .character(var data) = project.scenes[sceneIndex].timeline.tracks[trackIndex].clips[clipIndex].content,
                          data.characterID == characterID, data.expressionID == expressionID else { continue }
                    data.expressionID = nil
                    project.scenes[sceneIndex].timeline.tracks[trackIndex].clips[clipIndex].content = .character(data)
                }
            }
        }
    }


    func setDefaultExpression(characterID: UUID, expressionID: UUID?) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }),
              expressionID == nil || project.characters[index].expressions.contains(where: { $0.id == expressionID }) else { return }
        beginUndoableChange()
        project.characters[index].defaultExpressionID = expressionID
    }

    func setCharacterMouthSpeed(id: UUID, value: Double) {
        guard let index = project.characters.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(value, 0.5), 3.0)
        guard project.characters[index].defaultMouthSpeed != clamped else { return }
        beginUndoableChange()
        project.characters[index].defaultMouthSpeed = clamped
    }

    func setCharacterDefaultFlip(id: UUID, value: Bool) {
        guard let index = project.characters.firstIndex(where: { $0.id == id }),
              project.characters[index].defaultFlipHorizontal != value else { return }
        beginUndoableChange()
        project.characters[index].defaultFlipHorizontal = value
    }

    func saveCharacterPreset(characterID: UUID, name: String) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let character = project.characters[index]
        func visibility(_ nodes: [TachieLayerNode]) -> [UUID: Bool] {
            var result: [UUID: Bool] = [:]
            for node in nodes {
                result[node.id] = node.isVisible
                result.merge(visibility(node.children)) { _, new in new }
            }
            return result
        }
        beginUndoableChange()
        var preset = CharacterPreset(
            name: cleaned,
            baseImageFileName: character.baseImageFileName,
            mouthImageFileNames: character.mouthImageFileNames,
            eyeImageFileNames: character.eyeImageFileNames,
            defaultExpressionID: character.defaultExpressionID,
            layerVisibility: visibility(character.layerTree),
            animationDefaults: CharacterAnimationDefaults(character: character),
            mouthAnimationFrames: character.mouthAnimationFrames,
            eyeAnimationFrames: character.eyeAnimationFrames,
            animationBaseImageFileName: character.animationBaseImageFileName
        )
        preset.voice = CharacterVoicePreset(character: character)
        project.characters[index].presets.append(preset)
    }

    func applyCharacterPreset(characterID: UUID, presetID: UUID) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }),
              let preset = project.characters[index].presets.first(where: { $0.id == presetID }) else { return }
        func applying(_ nodes: [TachieLayerNode]) -> [TachieLayerNode] {
            nodes.map { source in
                var node = source
                node.isVisible = preset.layerVisibility[node.id] ?? node.isVisible
                node.children = applying(node.children)
                return node
            }
        }
        beginUndoableChange()
        project.characters[index].baseImageFileName = preset.baseImageFileName
        project.characters[index].mouthImageFileNames = preset.mouthImageFileNames
        project.characters[index].eyeImageFileNames = preset.eyeImageFileNames
        project.characters[index].mouthAnimationFrames = preset.mouthAnimationFrames
            ?? Character.defaultMouthAnimationFrames(images: preset.mouthImageFileNames)
        project.characters[index].eyeAnimationFrames = preset.eyeAnimationFrames
            ?? Character.defaultEyeAnimationFrames(images: preset.eyeImageFileNames)
        project.characters[index].animationBaseImageFileName = preset.animationBaseImageFileName
        project.characters[index].synchronizeLegacyAnimationImages()
        project.characters[index].defaultExpressionID = preset.defaultExpressionID
        project.characters[index].layerTree = applying(project.characters[index].layerTree)
        preset.voice?.apply(to: &project.characters[index])
        if let defaults = preset.animationDefaults {
            project.characters[index].defaultMouthSpeed = defaults.mouthSpeed
            project.characters[index].defaultFlipHorizontal = defaults.flipHorizontal
            project.characters[index].blinkEnabled = defaults.blinkEnabled
            project.characters[index].blinkInterval = defaults.blinkInterval
            project.characters[index].blinkDuration = defaults.blinkDuration
        }
        do {
            try regeneratePSDAnimationBase(at: index)
        } catch {
            errorMessage = "プリセットの口・目用基準画像を更新できませんでした：\(error.localizedDescription)"
        }
        imageProvider.invalidate(fileName: preset.baseImageFileName)
        for file in preset.mouthImageFileNames.values { imageProvider.invalidate(fileName: file) }
        for file in preset.eyeImageFileNames.values { imageProvider.invalidate(fileName: file) }
        for file in preset.mouthAnimationFrames?.compactMap(\.imageFileName) ?? [] { imageProvider.invalidate(fileName: file) }
        for file in preset.eyeAnimationFrames?.compactMap(\.imageFileName) ?? [] { imageProvider.invalidate(fileName: file) }
    }

    func removeCharacterPreset(characterID: UUID, presetID: UUID) {
        guard let index = project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        beginUndoableChange()
        project.characters[index].presets.removeAll { $0.id == presetID }
    }

    func removeCharacter(id: UUID) {
        guard project.characters.contains(where: { $0.id == id }) else { return }
        beginUndoableChange()
        project.characters.removeAll { $0.id == id }
        for sceneIndex in project.scenes.indices {
            for trackIndex in project.scenes[sceneIndex].timeline.tracks.indices {
                project.scenes[sceneIndex].timeline.tracks[trackIndex].clips.removeAll { clip in
                    guard case .character(let data) = clip.content else { return false }
                    return data.characterID == id
                }
            }
        }
        sanitizeSelectionAndScene()
    }

    // MARK: - Save / Open

    func save(to packageURL: URL) {
        do {
            try ProjectPackage.write(project: project, assetsDirectory: assetsDirectory, to: packageURL)
            currentPackageURL = packageURL
            let newAssetsDirectory = packageURL.appendingPathComponent("Assets", isDirectory: true)
            assetsDirectory = newAssetsDirectory
            imageProvider.updateAssetsDirectory(newAssetsDirectory)
            videoFrameProvider.updateAssetsDirectory(newAssetsDirectory)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveInPlace() -> Bool {
        guard let currentPackageURL else { return false }
        save(to: currentPackageURL)
        return true
    }

    func open(from packageURL: URL) {
        do {
            let (loadedProject, loadedAssetsDirectory) = try ProjectPackage.read(from: packageURL)
            project = loadedProject
            currentSceneID = loadedProject.scenes[0].id
            currentPackageURL = packageURL
            assetsDirectory = loadedAssetsDirectory
            imageProvider.updateAssetsDirectory(loadedAssetsDirectory)
            videoFrameProvider.updateAssetsDirectory(loadedAssetsDirectory)
            for index in project.characters.indices where project.characters[index].tachieKind == .psd {
                project.characters[index].reconnectPSDAnimationFrameSources()
                try regeneratePSDAnimationBase(at: index)
            }
            selectedClipIDs = []
            playhead = 0
            isPlaying = false
            undoStack.removeAll()
            redoStack.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Discards the in-memory project (after this, edits go to a fresh scratch asset
    /// folder again, same as at first launch) — doesn't touch anything already saved to
    /// disk.
    func resetToNewProject() {
        let newProject = Project(name: "無題のプロジェクト", scenes: [Scene(name: "メイン")])
        project = newProject
        currentSceneID = newProject.scenes[0].id
        currentPackageURL = nil
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let scratchAssets = support
            .appendingPathComponent("VMS", isDirectory: true)
            .appendingPathComponent(newProject.id.uuidString, isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
        assetsDirectory = scratchAssets
        imageProvider.updateAssetsDirectory(scratchAssets)
        videoFrameProvider.updateAssetsDirectory(scratchAssets)
        selectedClipIDs = []
        playhead = 0
        isPlaying = false
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

enum ClipEdge {
    case leading
    case trailing
}
