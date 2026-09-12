import Foundation
import VMSCore

extension ProjectStore {
    func applyVideoEditPlan(_ rawPlan: VideoEditPlan) throws {
        let assets = project.mediaAssets.filter { $0.kind == .video }
        let plan = try rawPlan.validated(against: assets)
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        beginUndoableChange()
        var timeline = currentTimeline
        while timeline.tracks.count < 3 { timeline.tracks.append(Track(name: "レイヤー\(timeline.tracks.count + 1)")) }
        if plan.replaceTimeline {
            for index in timeline.tracks.indices { timeline.tracks[index].clips.removeAll() }
        }
        timeline.tracks[0].name = "動画"
        timeline.tracks[1].name = "字幕"
        var selected: Set<UUID> = []
        for segment in plan.segments.sorted(by: { $0.timelineStart < $1.timelineStart }) {
            guard let asset = byID[segment.assetID] else { continue }
            let video = Clip(
                startTime: segment.timelineStart,
                duration: segment.sourceDuration,
                content: .video(VideoClipData(
                    assetID: asset.id,
                    fileName: asset.fileName,
                    sourceStartTime: segment.sourceStart
                ))
            )
            timeline.tracks[0].clips.append(video)
            selected.insert(video.id)
            if let caption = segment.caption, !caption.isEmpty {
                timeline.tracks[1].clips.append(Clip(
                    startTime: segment.timelineStart,
                    duration: segment.sourceDuration,
                    content: .text(TextClipData(text: caption))
                ))
            }
        }
        currentTimeline = timeline
        selectedClipIDs = selected
        playhead = 0
    }
}
