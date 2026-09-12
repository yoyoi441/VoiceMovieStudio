import Foundation
import VMSCore

extension ProjectStore {
    func addRemoteAISubtitles(_ analysis: RemoteAIAnalysis) {
        guard let asset = project.mediaAssets.first(where: { $0.id == analysis.assetID }) else { return }
        let sourceClips = currentTimeline.tracks.flatMap(\.clips).filter { clip in
            switch clip.content {
            case .video(let data): return data.assetID == asset.id
            case .audio(let data): return data.fileName == asset.fileName
            default: return false
            }
        }
        guard !sourceClips.isEmpty else { errorMessage = "対象素材が現在のタイムラインにありません。"; return }
        beginUndoableChange()
        var timeline = currentTimeline
        while timeline.tracks.count < 2 { timeline.tracks.append(Track(name: "テキスト")) }
        var created = Set<UUID>()
        for sourceClip in sourceClips {
            let sourceOffset: Double
            if case .video(let data) = sourceClip.content { sourceOffset = data.sourceStartTime } else { sourceOffset = 0 }
            for segment in analysis.transcript where segment.end > sourceOffset && segment.start < sourceOffset + sourceClip.duration {
                let start = sourceClip.startTime + max(0, segment.start - sourceOffset)
                let end = min(sourceClip.endTime, sourceClip.startTime + segment.end - sourceOffset)
                guard end > start, !segment.text.isEmpty else { continue }
                let clip = Clip(startTime: start, duration: end - start, content: .text(TextClipData(text: segment.text)))
                timeline.tracks[1].clips.append(clip)
                created.insert(clip.id)
            }
        }
        timeline.tracks[1].clips.sort { $0.startTime < $1.startTime }
        currentTimeline = timeline
        selectedClipIDs = created
    }

    func createRemoteAIClips(_ analysis: RemoteAIAnalysis) {
        guard let asset = project.mediaAssets.first(where: { $0.id == analysis.assetID }), asset.kind == .video else {
            errorMessage = "クリップ作成には動画素材が必要です。"; return
        }
        let selected = analysis.highlights.filter(\.isSelected).sorted { $0.start < $1.start }
        guard !selected.isEmpty else { errorMessage = "使用するクリップ候補を選択してください。"; return }
        beginUndoableChange()
        var timeline = currentTimeline
        if timeline.tracks.isEmpty { timeline.tracks = Timeline.defaultLayerStack() }
        var cursor = playhead
        var ids = Set<UUID>()
        for candidate in selected {
            let duration = max(0.1, min(asset.duration, candidate.end) - max(0, candidate.start))
            let clip = Clip(startTime: cursor, duration: duration, content: .video(VideoClipData(assetID: asset.id, fileName: asset.fileName, sourceStartTime: max(0, candidate.start))))
            timeline.tracks[0].clips.append(clip)
            ids.insert(clip.id)
            cursor += duration
        }
        timeline.tracks[0].clips.sort { $0.startTime < $1.startTime }
        currentTimeline = timeline
        selectedClipIDs = ids
    }
}
