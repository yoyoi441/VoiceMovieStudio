import AppKit
import SwiftUI
import VMSCore

/// §6: one clip's rendering + interaction on the timeline — click select (with ⌘/⇧
/// modifiers), drag to move (the whole multi-selection moves together), drag the edges to
/// resize, snapping to nearby clip edges/the playhead, and a locked visual state. All
/// coordinate math goes through `TimelineGeometry` (§5/§11: one shared conversion, not
/// `time * pixelsPerSecond` re-derived per view).
struct TimelineItemView: View {
    let clip: Clip
    let geometry: TimelineGeometry

    @Environment(ProjectStore.self) private var store

    /// Captured once at the start of a move-drag: every selected clip's id → original
    /// start time, so the whole selection can be shifted by the same delta. Empty when
    /// not currently dragging.
    @State private var moveOriginalStartTimes: [UUID: TimeInterval] = [:]
    @State private var isMoveDragging = false
    @State private var isResizing = false

    private let edgeHandleWidth: CGFloat = 6
    private let snapThresholdPixels: Double = 8

    var body: some View {
        let width = geometry.width(for: clip.duration)
        let isSelected = store.isSelected(clip.id)
        let isLocked = clip.isLocked || (store.track(containing: clip.id)?.isLocked ?? false)

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Theme.controlCornerRadius)
                .fill(color.opacity(isSelected ? 0.95 : (isLocked ? 0.35 : 0.7)))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlCornerRadius)
                        .strokeBorder(isSelected ? Theme.selectionBorder : Color.black.opacity(0.25), lineWidth: isSelected ? 2 : 1)
                )

            HStack(spacing: 3) {
                if isLocked {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                }
                Text(label).lineLimit(1)
            }
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 5)
        }
        .frame(width: width, height: 28)
        .offset(x: geometry.x(for: clip.startTime))
        .opacity(isLocked ? 0.7 : 1)
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .overlay(alignment: .leading) { if !isLocked { resizeHandle(.leading) } }
        .overlay(alignment: .trailing) { if !isLocked { resizeHandle(.trailing) } }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help(isLocked ? "\(label)(ロック中)" : label)
    }

    // MARK: - Selection

    private func handleTap() {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            store.selectClip(clip.id, range: true)
        } else if modifiers.contains(.command) {
            store.selectClip(clip.id, extend: true)
        } else {
            store.selectClip(clip.id)
        }
    }

    // MARK: - Move

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineContent"))
            .onChanged { value in
                guard !(clip.isLocked || (store.track(containing: clip.id)?.isLocked ?? false)) else { return }
                // A zero-distance drag also covers an ordinary click. Delay the actual
                // move until the pointer has travelled far enough, while selecting at
                // pointer-down so the whole visible body of the clip is responsive.
                if !isMoveDragging {
                    isMoveDragging = true
                    handleTap()
                }
                guard abs(value.translation.width) >= 2 || abs(value.translation.height) >= 2 else { return }
                if moveOriginalStartTimes.isEmpty {
                    store.beginUndoableChange()
                    moveOriginalStartTimes = Dictionary(
                        uniqueKeysWithValues: store.selectedClips.map { ($0.id, $0.startTime) }
                    )
                }
                guard let originalStart = moveOriginalStartTimes[clip.id] else { return }
                let deltaTime = geometry.deltaTime(forDeltaX: value.translation.width)
                let proposedStart = max(0, originalStart + deltaTime)
                let snappedStart = snap(proposedStart, excluding: Set(moveOriginalStartTimes.keys))
                let appliedDelta = snappedStart - originalStart
                store.moveSelectedClips(originalStartTimes: moveOriginalStartTimes, delta: appliedDelta)
            }
            .onEnded { _ in
                moveOriginalStartTimes = [:]
                isMoveDragging = false
            }
    }

    // MARK: - Resize

    private func resizeHandle(_ edge: ClipEdge) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: edgeHandleWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("timelineContent"))
                    .onChanged { value in
                        guard !(clip.isLocked || (store.track(containing: clip.id)?.isLocked ?? false)) else { return }
                        if !isResizing {
                            isResizing = true
                            store.beginUndoableChange()
                        }
                        let rawTime = geometry.time(for: value.location.x)
                        let snapped = snap(rawTime, excluding: [clip.id])
                        store.resizeClip(id: clip.id, edge: edge, to: snapped)
                    }
                    .onEnded { _ in isResizing = false }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    // MARK: - Snap

    private func snap(_ time: TimeInterval, excluding: Set<UUID>) -> TimeInterval {
        guard store.isSnapEnabled else { return time }
        let threshold = snapThresholdPixels / max(geometry.pixelsPerSecond, 1)
        var candidates: [TimeInterval] = [store.playhead, 0]
        for track in store.currentTimeline.tracks {
            for other in track.clips where !excluding.contains(other.id) {
                candidates.append(other.startTime)
                candidates.append(other.endTime)
            }
        }
        guard let nearest = candidates.min(by: { abs($0 - time) < abs($1 - time) }), abs(nearest - time) <= threshold else {
            return time
        }
        return nearest
    }

    // MARK: - Appearance

    private var color: Color {
        switch clip.content {
        case .text: return Theme.textItemColor
        case .character: return Theme.characterItemColor
        case .audio: return Theme.audioItemColor
        case .image: return Theme.imageItemColor
        case .video: return Theme.videoItemColor
        }
    }

    private var label: String {
        switch clip.content {
        case .text(let data): return data.text
        case .character(let data): return store.project.character(withID: data.characterID)?.name ?? "キャラクター"
        case .audio(let data): return data.sourceText ?? data.fileName
        case .image(let data): return data.fileName
        case .video(let data): return data.fileName
        }
    }
}
