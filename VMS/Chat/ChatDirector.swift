import Foundation
import VMSCore

protocol ChatDirector: Sendable {
    func createPlan(
        instruction: String,
        materials: [AnalyzedVideoMaterial],
        history: [ProjectChatMessage]
    ) async throws -> VideoEditPlan
}

struct LocalChatDirector: ChatDirector {
    func createPlan(
        instruction: String,
        materials: [AnalyzedVideoMaterial],
        history: [ProjectChatMessage]
    ) async throws -> VideoEditPlan {
        let target = Self.targetDuration(from: instruction)
        var cursor = 0.0
        var segments: [VideoEditSegment] = []
        let available = materials.filter { $0.asset.duration > 0 }
        let perAsset = target.map { $0 / Double(max(available.count, 1)) }
        for material in available {
            let duration = min(material.asset.duration, perAsset ?? material.asset.duration)
            guard duration > 0 else { continue }
            segments.append(.init(
                assetID: material.asset.id,
                sourceStart: 0,
                sourceDuration: duration,
                timelineStart: cursor,
                caption: nil
            ))
            cursor += duration
        }
        return VideoEditPlan(
            title: "自動構成",
            summary: "OpenAI APIキーが未設定のため、素材を順番に並べた簡易編集案です。",
            segments: segments
        )
    }

    private static func targetDuration(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:秒|seconds?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}
