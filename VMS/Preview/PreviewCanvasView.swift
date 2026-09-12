import AppKit
import SwiftUI
import VMSCore

/// Scales `CompositeFrameView` (rendered at the project's true resolution) down to fit
/// the available preview area, so what's on screen matches what export produces. Adds a
/// draggable handle over every text/character clip visible at the playhead, so their
/// on-canvas position can be set by dragging directly instead of only via the inspector.
struct PreviewCanvasView: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        let resolution = store.project.resolution

        GeometryReader { geometry in
            let scale = min(geometry.size.width / resolution.width, geometry.size.height / resolution.height)
            let displayedSize = CGSize(width: resolution.width * scale, height: resolution.height * scale)
            let topLeft = CGPoint(
                x: geometry.size.width / 2 - displayedSize.width / 2,
                y: geometry.size.height / 2 - displayedSize.height / 2
            )

            ZStack(alignment: .topLeading) {
                CompositeFrameView(
                    project: store.project,
                    timeline: store.currentTimeline,
                    time: store.playhead,
                    imageProvider: store.imageProvider,
                    videoFrameProvider: store.videoFrameProvider
                )
                    .scaleEffect(scale)
                    .frame(width: displayedSize.width, height: displayedSize.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                if store.isPreviewDirectManipulationEnabled {
                    ForEach(positionableClips) { clip in
                        positionHandle(for: clip, topLeft: topLeft, displayedSize: displayedSize)
                    }
                }
            }
        }
        .aspectRatio(resolution.width / resolution.height, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
        .task(id: videoFrameRequestID) {
            for clip in visibleVideoClips {
                guard case .video(let data) = clip.content else { continue }
                await store.videoFrameProvider.prepare(
                    fileName: data.fileName,
                    sourceTime: data.sourceStartTime + max(0, store.playhead - clip.startTime),
                    frameRate: store.project.frameRate
                )
            }
        }
    }

    private func positionHandle(for clip: Clip, topLeft: CGPoint, displayedSize: CGSize) -> some View {
        let point = position(of: clip)
        let offset = handleOffset(for: clip, displayedSize: displayedSize)
        let screenPoint = CGPoint(
            x: topLeft.x + (point.x + 1) * 0.5 * displayedSize.width + offset.x,
            y: topLeft.y + (point.y + 1) * 0.5 * displayedSize.height + offset.y
        )
        let isSelected = store.selectedClipID == clip.id

        return Circle()
            .fill(isSelected ? Color.accentColor : Color.white.opacity(0.7))
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
            .shadow(radius: 1)
            .position(screenPoint)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        store.selectedClipID = clip.id
                        let newX = ((value.location.x - topLeft.x - offset.x) / displayedSize.width) * 2 - 1
                        let newY = ((value.location.y - topLeft.y - offset.y) / displayedSize.height) * 2 - 1
                        store.setPosition(clipID: clip.id, x: newX, y: newY)
                    }
            )
    }

    /// Text uses a leading-edge anchor in the renderer. Measure the rendered block so
    /// its drag handle can sit above the visual centre instead of covering the first glyph.
    private func handleOffset(for clip: Clip, displayedSize: CGSize) -> CGPoint {
        guard case .text(let data) = clip.content else { return .zero }
        let resolution = store.project.resolution
        let canvasFontSize = data.fontSize * resolution.width / 1920
        let font = NSFont(name: data.fontName, size: canvasFontSize)
            ?? NSFont.systemFont(ofSize: canvasFontSize, weight: data.isBold ? .bold : .regular)
        let maximumWidth = data.wrapMode == .none ? CGFloat.greatestFiniteMagnitude : data.wrapWidth * resolution.width / 1920
        let bounds = (data.text as NSString).boundingRect(
            with: CGSize(width: maximumWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let previewScale = displayedSize.width / resolution.width
        let width = min(bounds.width, maximumWidth) * previewScale
        let height = bounds.height * previewScale
        return CGPoint(x: width / 2, y: -(height / 2 + 14))
    }

    private var positionableClips: [Clip] {
        store.currentTimeline.tracks
            .filter(\.isVisible)
            .flatMap { $0.clips(at: store.playhead) }
            .filter { clip in
                // These effects move the drawn anchor; edit its base X/Y in the inspector.
                guard !clip.isLocked, !clip.effects.effectsList.contains(where: {
                    guard $0.isEnabled, case .visual(let v) = $0.kind else { return false }
                    return [.move, .shake, .spin, .pulse, .verticalFlip].contains(v.type)
                }) else { return false }
                switch clip.content {
                case .text, .character, .image, .video: return true
                case .audio: return false
                }
            }
    }

    private func position(of clip: Clip) -> CodablePoint {
        switch clip.content {
        case .text(let data): return data.position
        case .character(let data): return data.presentation(at: store.playhead - clip.startTime).position
        case .image(let data): return data.position
        case .video(let data): return data.position
        case .audio: return CodablePoint(x: 0, y: 0)
        }
    }

    private var visibleVideoClips: [Clip] {
        store.currentTimeline.tracks
            .filter(\.isVisible)
            .flatMap { $0.clips(at: store.playhead) }
            .filter { if case .video = $0.content { return true }; return false }
    }

    private var videoFrameRequestID: String {
        let frame = Int((store.playhead * max(store.project.frameRate, 1)).rounded())
        return "\(store.currentSceneID.uuidString)-\(frame)-\(visibleVideoClips.map(\.id).map(\.uuidString).joined())"
    }
}
