import Foundation

/// Talks to a locally running VOICEVOX Engine (the `voicevox_engine` process the VOICEVOX
/// app bundles, or a standalone engine build). Default port 50021 matches VOICEVOX's own
/// default; the macOS app exposes the same API as Windows/Linux.
public final class VoiceVoxClient: VoiceEngine, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:50021")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func availableSpeakers() async throws -> [VoiceSpeaker] {
        let url = baseURL.appendingPathComponent("speakers")
        let data = try await get(url)
        let decoded = try decode([VoiceVoxSpeakerResponse].self, from: data)
        return decoded.flatMap { speaker in
            speaker.styles.filter { $0.type == nil || $0.type == "talk" }.map { style in
                VoiceSpeaker(id: style.id, name: speaker.name, styleName: style.name)
            }
        }
    }

    public func synthesize(text: String, speakerID: Int, settings: VoiceSettings) async throws -> SynthesizedSpeech {
        let settings = settings.validatedForVoiceVox()
        var query = try await audioQuery(text: text, speakerID: speakerID)
        query.speedScale = settings.speed
        query.pitchScale = settings.pitch
        query.intonationScale = settings.intonation
        query.volumeScale = settings.volume
        query.prePhonemeLength = settings.preSilence
        query.postPhonemeLength = settings.postSilence

        let audioData = try await synthesis(query: query, speakerID: speakerID)
        return SynthesizedSpeech(
            audioData: audioData,
            moraTimings: query.moraTimings(),
            duration: query.totalDuration()
        )
    }

    // MARK: - Endpoints

    private func audioQuery(text: String, speakerID: Int) async throws -> VoiceVoxAudioQuery {
        var components = URLComponents(url: baseURL.appendingPathComponent("audio_query"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "speaker", value: String(speakerID))
        ]
        let data = try await post(components.url!, body: Data())
        return try decode(VoiceVoxAudioQuery.self, from: data)
    }

    private func synthesis(query: VoiceVoxAudioQuery, speakerID: Int) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("synthesis"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "speaker", value: String(speakerID))]
        let body = try encode(query)
        return try await post(components.url!, body: body, contentType: "application/json")
    }

    // MARK: - HTTP plumbing

    private func get(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            try Self.checkStatus(response, data: data)
            return data
        } catch let error as VoiceEngineError {
            throw error
        } catch {
            throw VoiceEngineError.engineUnreachable(underlying: error)
        }
    }

    private func post(_ url: URL, body: Data, contentType: String = "application/json") async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await session.data(for: request)
            try Self.checkStatus(response, data: data)
            return data
        } catch let error as VoiceEngineError {
            throw error
        } catch {
            throw VoiceEngineError.engineUnreachable(underlying: error)
        }
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw VoiceEngineError.unexpectedResponse("HTTP \(status): \(body)")
        }
    }

    // VOICEVOX's JSON mixes snake_case and camelCase keys within the same object (see
    // the comment atop VoiceVoxModels.swift), so every wire type spells out its own
    // `CodingKeys` — no blanket key conversion strategy here.

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw VoiceEngineError.unexpectedResponse(String(describing: error))
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}
