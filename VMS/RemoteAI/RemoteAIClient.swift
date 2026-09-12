import Foundation
import VMSCore

struct RemoteAIClient: Sendable {
    var baseURL: URL
    var token: String
    var session: URLSession = .shared

    func health() async throws -> RemoteAINodeInfo {
        try await request(path: "/v1/health", method: "GET", body: nil, extraHeaders: [:])
    }

    func submitTranscription(fileURL: URL, language: String) async throws -> RemoteAIJobStatus {
        var request = authorizedRequest(path: "/v1/jobs", method: "POST")
        request.setValue("transcription", forHTTPHeaderField: "X-Job-Type")
        request.setValue(fileURL.lastPathComponent, forHTTPHeaderField: "X-Filename")
        request.setValue(language, forHTTPHeaderField: "X-Language")
        request.setValue(String((try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), forHTTPHeaderField: "Content-Length")
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        return try decode(RemoteAIJobStatus.self, data: data, response: response)
    }

    func submitHighlights(transcript: [TranscriptSegment], instruction: String, model: String?) async throws -> RemoteAIJobStatus {
        struct Payload: Encodable { var transcript: [TranscriptSegment]; var instruction: String; var model: String? }
        let body = try JSONEncoder().encode(Payload(transcript: transcript, instruction: instruction, model: model))
        return try await request(path: "/v1/jobs", method: "POST", body: body, extraHeaders: ["X-Job-Type": "highlights"])
    }

    func submitStoryboardPlan(
        lines: [ScenarioDraftLine],
        characters: [Character],
        instruction: String,
        model: String?
    ) async throws -> RemoteAIJobStatus {
        struct Line: Encodable {
            var dialogue: String
            var speakerName: String?
        }
        struct Payload: Encodable {
            var lines: [Line]
            var characters: [String]
            var instruction: String
            var model: String?
        }
        let namesByID = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0.name) })
        let payload = Payload(
            lines: lines.map {
                Line(
                    dialogue: $0.dialogue,
                    speakerName: $0.speakerID.flatMap { namesByID[$0] } ?? $0.unresolvedSpeakerName
                )
            },
            characters: characters.map(\.name),
            instruction: instruction,
            model: model
        )
        let body = try JSONEncoder().encode(payload)
        return try await request(
            path: "/v1/jobs", method: "POST", body: body,
            extraHeaders: ["X-Job-Type": "storyboardPlanning"]
        )
    }

    func status(id: UUID) async throws -> RemoteAIJobStatus {
        try await request(path: "/v1/jobs/\(id.uuidString)", method: "GET", body: nil, extraHeaders: [:])
    }

    func cancel(id: UUID) async throws {
        let _: RemoteAIJobStatus = try await request(path: "/v1/jobs/\(id.uuidString)", method: "DELETE", body: nil, extraHeaders: [:])
    }

    private func request<T: Decodable>(path: String, method: String, body: Data?, extraHeaders: [String: String]) async throws -> T {
        var request = authorizedRequest(path: path, method: method)
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (key, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        return try decode(T.self, data: data, response: response)
    }

    private func authorizedRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.timeoutInterval = 60 * 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ClientError.decode(error.localizedDescription) }
    }

    enum ClientError: LocalizedError {
        case invalidResponse, http(Int, String), decode(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "AIノードから正しい応答を受け取れませんでした。"
            case .http(let code, let detail): return "AIノードエラー（\(code)）: \(detail)"
            case .decode(let detail): return "AIノードの応答を読み取れません: \(detail)"
            }
        }
    }
}
