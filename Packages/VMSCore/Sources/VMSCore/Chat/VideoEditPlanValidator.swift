import Foundation

public enum VideoEditPlanValidationError: Error, LocalizedError {
    case noSegments
    case unknownAsset(UUID)
    case invalidRange(UUID)

    public var errorDescription: String? {
        switch self {
        case .noSegments: return "編集プランに動画セグメントがありません。"
        case .unknownAsset(let id): return "編集プランが未知の素材を参照しています: \(id.uuidString)"
        case .invalidRange(let id): return "素材の時間範囲が不正です: \(id.uuidString)"
        }
    }
}

public extension VideoEditPlan {
    func validated(against assets: [MediaAsset]) throws -> VideoEditPlan {
        guard !segments.isEmpty else { throw VideoEditPlanValidationError.noSegments }
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let cleaned = try segments.prefix(200).map { segment -> VideoEditSegment in
            guard let asset = byID[segment.assetID], asset.kind == .video else {
                throw VideoEditPlanValidationError.unknownAsset(segment.assetID)
            }
            guard segment.sourceStart.isFinite, segment.sourceDuration.isFinite,
                  segment.timelineStart.isFinite, segment.sourceDuration > 0 else {
                throw VideoEditPlanValidationError.invalidRange(segment.assetID)
            }
            let sourceStart = min(max(0, segment.sourceStart), max(0, asset.duration - 0.1))
            let duration = min(max(0.1, segment.sourceDuration), max(0.1, asset.duration - sourceStart))
            return VideoEditSegment(
                id: segment.id,
                assetID: segment.assetID,
                sourceStart: sourceStart,
                sourceDuration: duration,
                timelineStart: max(0, segment.timelineStart),
                caption: segment.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return VideoEditPlan(title: title, summary: summary, replaceTimeline: replaceTimeline, segments: cleaned)
    }
}
