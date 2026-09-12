import Foundation
import VMSCore

/// OpenAI Responses API implementation. Representative JPEG frames are sent as data URLs;
/// the original movie files never leave the Mac. The response is constrained by a strict
/// JSON schema and then validated again locally before it can mutate the timeline.
struct OpenAIChatDirector: ChatDirector {
    var apiKey: String
    var model: String
    var session: URLSession = .shared

    func createPlan(
        instruction: String,
        materials: [AnalyzedVideoMaterial],
        history: [ProjectChatMessage]
    ) async throws -> VideoEditPlan {
        var content: [[String: Any]] = [[
            "type": "input_text",
            "text": prompt(instruction: instruction, materials: materials, history: history)
        ]]
        for material in materials.prefix(8) {
            for frame in material.frames.prefix(3) {
                content.append([
                    "type": "input_text",
                    "text": "asset_id=\(material.asset.id.uuidString) time=\(String(format: "%.2f", frame.time))s"
                ])
                content.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(frame.jpegData.base64EncodedString())",
                    "detail": "low"
                ])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "store": false,
            "instructions": "You are a Japanese video editor. Return a practical edit plan using only supplied asset IDs and valid source ranges. Keep pacing coherent and captions concise.",
            "input": [["role": "user", "content": content]],
            "text": ["format": Self.responseFormat]
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DirectorError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
            throw DirectorError.api(status: http.statusCode, detail: detail ?? String(data: data, encoding: .utf8) ?? "")
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let jsonText = Self.outputText(from: object), let jsonData = jsonText.data(using: .utf8) else {
            throw DirectorError.missingOutput
        }
        return try JSONDecoder().decode(VideoEditPlan.self, from: jsonData)
    }

    private func prompt(
        instruction: String,
        materials: [AnalyzedVideoMaterial],
        history: [ProjectChatMessage]
    ) -> String {
        let list = materials.map {
            "- id=\($0.asset.id.uuidString) name=\($0.asset.originalName) duration=\(String(format: "%.2f", $0.asset.duration))s"
        }.joined(separator: "\n")
        let recent = history.suffix(8).map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
        return """
        ユーザー指示:
        \(instruction)

        使用可能な動画素材:
        \(list)

        直近の会話:
        \(recent)

        timelineStartが重複しないように並べ、sourceStart + sourceDurationは必ず素材の長さ以内にしてください。
        captionが不要な場合はnullにしてください。
        """
    }

    private static var responseFormat: [String: Any] { [
        "type": "json_schema",
        "name": "video_edit_plan",
        "strict": true,
        "schema": [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "replaceTimeline": ["type": "boolean"],
                "segments": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "id": ["type": "string", "format": "uuid"],
                            "assetID": ["type": "string", "format": "uuid"],
                            "sourceStart": ["type": "number"],
                            "sourceDuration": ["type": "number"],
                            "timelineStart": ["type": "number"],
                            "caption": ["type": ["string", "null"]]
                        ],
                        "required": ["id", "assetID", "sourceStart", "sourceDuration", "timelineStart", "caption"]
                    ]
                ]
            ],
            "required": ["title", "summary", "replaceTimeline", "segments"]
        ]
    ] }

    private static func outputText(from object: [String: Any]?) -> String? {
        if let direct = object?["output_text"] as? String, !direct.isEmpty { return direct }
        guard let output = object?["output"] as? [[String: Any]] else { return nil }
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "output_text" {
                if let text = part["text"] as? String { return text }
            }
        }
        return nil
    }

    enum DirectorError: LocalizedError {
        case invalidResponse
        case api(status: Int, detail: String)
        case missingOutput

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "OpenAI APIから正しいHTTP応答を受け取れませんでした。"
            case .api(let status, let detail): return "OpenAI APIエラー (\(status)): \(detail)"
            case .missingOutput: return "OpenAI APIの応答に編集プランがありません。"
            }
        }
    }
}
