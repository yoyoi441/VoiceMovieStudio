import AppKit
import SwiftUI
import VMSCore

struct TimelineView: View {
    @Environment(ProjectStore.self) private var store
    @FocusState private var isFocused: Bool
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var isMarqueeCursorActive = false

    var body: some View {
        let tracks = store.currentTimeline.tracks
        let geometry = TimelineGeometry(pixelsPerSecond: store.pixelsPerSecond)
        let contentDuration = max(store.currentTimeline.duration + 5, 30)
        let contentWidth = geometry.x(for: contentDuration)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: Theme.trackHeaderWidth)
                ScrollView(.horizontal, showsIndicators: false) {
                    TimeRuler(
                        duration: contentDuration,
                        frameRate: store.project.frameRate,
                        geometry: geometry,
                        playhead: Binding(get: { store.playhead }, set: { store.playhead = $0 })
                    )
                    .frame(width: contentWidth, height: Theme.rulerHeight)
                }
                .frame(height: Theme.rulerHeight)
            }

            Divider()

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tracks) { track in
                            TrackHeaderView(track: track)
                                .frame(width: Theme.trackHeaderWidth, height: Theme.rowHeight)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(tracks) { track in
                                trackLane(track: track, geometry: geometry)
                                    .frame(width: contentWidth, height: Theme.rowHeight)
                            }
                        }

                        Playhead(time: store.playhead, geometry: geometry, height: CGFloat(tracks.count) * Theme.rowHeight)

                        if let rect = marqueeRect {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.16))
                                .overlay {
                                    Rectangle()
                                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                }
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                                .accessibilityLabel("範囲選択")
                                .allowsHitTesting(false)
                        }
                    }
                    .coordinateSpace(name: "timelineContent")
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { store.timelineViewportWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newValue in store.timelineViewportWidth = newValue }
                }
            )

            Divider()

            HStack {
                Button {
                    store.addTrack()
                } label: {
                    Label("レイヤー追加", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .font(.caption)
                Spacer()
                Text("\(tracks.count) レイヤー")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Theme.canvasBackground)
        .focusable()
        .focused($isFocused)
        .onChange(of: store.selectedClipIDs) { _, newValue in
            if !newValue.isEmpty { isFocused = true }
        }
        .onDisappear { finishMarquee() }
        // Selection-editing shortcuts live here (scoped to timeline focus) rather than in
        // the app's global `.commands`, so ⌘C/⌘X/⌘V/⌘A/Delete keep behaving normally
        // whenever a text field (scene/track rename, clip text, …) has focus instead.
        .onKeyPress { press in
            if press.modifiers.contains(.command) {
                switch press.characters.lowercased() {
                case "c": store.copySelected(); return .handled
                case "x": store.cutSelected(); return .handled
                case "v": store.pasteClipboard(); return .handled
                case "a": store.selectAll(); return .handled
                case "d": store.duplicateSelected(); return .handled
                default: return .ignored
                }
            }
            if press.key == .delete || press.key == .deleteForward {
                store.deleteSelected()
                return .handled
            }
            return .ignored
        }
    }

    private var marqueeRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func trackLane(track: Track, geometry: TimelineGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(track.isLocked ? Theme.disabledFill : Color.black.opacity(0.15))
                .contentShape(Rectangle())
                .gesture(seekGesture(geometry: geometry))
                .simultaneousGesture(marqueeGesture(geometry: geometry))
            ForEach(track.clips) { clip in
                TimelineItemView(clip: clip, geometry: geometry)
                    .padding(.vertical, 3)
            }
        }
        .border(Theme.border)
    }

    private func seekGesture(geometry: TimelineGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineContent"))
            .onChanged { value in
                store.playhead = geometry.time(for: value.location.x)
                isFocused = true
            }
    }

    /// Hold an empty part of a lane briefly, then drag to surround items. Keeping this
    /// separate from the zero-distance seek gesture preserves click/drag scrubbing.
    private func marqueeGesture(geometry: TimelineGeometry) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("timelineContent")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if marqueeStart == nil {
                    marqueeStart = drag.startLocation
                    beginMarqueeCursor()
                }
                marqueeCurrent = drag.location
                isFocused = true
            }
            .onEnded { value in
                defer { finishMarquee() }
                guard case .second(true, let drag?) = value else { return }
                let start = marqueeStart ?? drag.startLocation
                let end = drag.location
                let lowerTrack = max(0, Int(floor(min(start.y, end.y) / Theme.rowHeight)))
                let upperTrack = min(
                    max(0, store.currentTimeline.tracks.count - 1),
                    Int(floor(max(start.y, end.y) / Theme.rowHeight))
                )
                guard lowerTrack <= upperTrack else { return }
                let modifiers = NSEvent.modifierFlags
                store.selectClips(
                    intersecting: geometry.time(for: min(start.x, end.x))...geometry.time(for: max(start.x, end.x)),
                    trackRange: lowerTrack...upperTrack,
                    extending: modifiers.contains(.command) || modifiers.contains(.shift)
                )
            }
    }

    private func beginMarqueeCursor() {
        guard !isMarqueeCursorActive else { return }
        NSCursor.crosshair.push()
        isMarqueeCursorActive = true
    }

    private func finishMarquee() {
        marqueeStart = nil
        marqueeCurrent = nil
        if isMarqueeCursorActive {
            NSCursor.pop()
            isMarqueeCursorActive = false
        }
    }
}

private struct TrackHeaderView: View {
    @Environment(ProjectStore.self) private var store
    let track: Track

    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up")
                .font(.caption2)
                .foregroundColor(.secondary)

            if isEditingName {
                TextField("レイヤー名", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($isFieldFocused)
                    .onSubmit { commitRename() }
                    .onChange(of: isFieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(track.name)
                    .font(.caption)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginRename() }
            }

            Spacer()

            Button {
                store.beginUndoableChange()
                var updated = track
                updated.isLocked.toggle()
                replaceTrack(updated)
            } label: {
                Image(systemName: track.isLocked ? "lock.fill" : "lock.open")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(track.isLocked ? "レイヤーのロックを解除" : "レイヤーをロック")

            Button {
                store.removeTrack(id: track.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(Theme.panelBackground)
        .overlay(Rectangle().stroke(Theme.border))
    }

    private func beginRename() {
        editedName = track.name
        isEditingName = true
        isFieldFocused = true
    }

    private func commitRename() {
        guard isEditingName else { return }
        isEditingName = false
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            store.renameTrack(id: track.id, to: trimmed)
        }
    }

    private func replaceTrack(_ updated: Track) {
        var timeline = store.currentTimeline
        guard let index = timeline.tracks.firstIndex(where: { $0.id == updated.id }) else { return }
        timeline.tracks[index] = updated
        store.currentTimeline = timeline
    }
}
