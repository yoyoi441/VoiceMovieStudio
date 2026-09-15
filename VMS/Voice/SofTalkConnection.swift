import Foundation
import Observation
import VMSCore

struct SofTalkBridgeClient: Sendable {
    var baseURL: URL
    var token: String
    var session: URLSession = .shared

    func health() async throws -> SofTalkSupport.BridgeInfo {
        let request = authorizedRequest(path: "v1/health", method: "GET")
        let (data, response) = try await session.data(for: request)
        guard data.count <= 1_000_000 else { throw ClientError.responseTooLarge }
        return try decode(SofTalkSupport.BridgeInfo.self, data: data, response: response)
    }

    func launch() async throws {
        let request = authorizedRequest(path: "v1/launch", method: "POST")
        let (data, response) = try await session.data(for: request)
        let _: StatusResponse = try decode(StatusResponse.self, data: data, response: response)
    }

    func synthesize(_ value: SofTalkSupport.SynthesisRequest) async throws -> Data {
        var request = authorizedRequest(path: "v1/synthesize", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(value)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw error(data: data, status: http.statusCode) }
        guard data.count >= 12, data.count <= 512 * 1024 * 1024,
              data.prefix(4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WAVE".utf8) else {
            throw ClientError.invalidAudio
        }
        return data
    }

    private func authorizedRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw error(data: data, status: http.statusCode) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ClientError.decode(error.localizedDescription) }
    }

    private func error(data: Data, status: Int) -> ClientError {
        let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error)
            ?? String(data: data, encoding: .utf8) ?? ""
        return .http(status, detail)
    }

    private struct StatusResponse: Decodable { var status: String }
    private struct ErrorResponse: Decodable { var error: String }

    enum ClientError: LocalizedError {
        case invalidResponse
        case invalidAudio
        case responseTooLarge
        case http(Int, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "SofTalk連携先から正しい応答を受け取れませんでした。"
            case .invalidAudio: "SofTalk連携先が有効なWAV音声を返しませんでした。"
            case .responseTooLarge: "SofTalk連携先の応答が大きすぎるため停止しました。"
            case .http(let status, let detail): "SofTalk連携エラー（\(status)）: \(detail)"
            case .decode(let detail): "SofTalk連携先の応答を読み取れません: \(detail)"
            }
        }
    }
}

@Observable
@MainActor
final class SofTalkConnectionController {
    static let shared = SofTalkConnectionController()

    private static let endpointKey = "softalkBridge.endpoint"
    private static let tokenAccount = "softalk-bridge-token"

    var endpoint: String
    var tokenDraft: String
    var info: SofTalkSupport.BridgeInfo?
    var isWorking = false
    var message = "Windows側の連携先を設定してください。"

    private init() {
        endpoint = UserDefaults.standard.string(forKey: Self.endpointKey) ?? ""
        tokenDraft = KeychainStore.read(account: Self.tokenAccount) ?? ""
    }

    var profiles: [SofTalkSupport.Profile] {
        let received = info?.profiles ?? []
        return SofTalkSupport.builtInProfiles.map { builtIn in
            let configured = received.first { $0.id == builtIn.id }?.isConfigured ?? false
            return .init(id: builtIn.id, displayName: builtIn.displayName, isConfigured: configured)
        }
    }

    func profile(id: String) -> SofTalkSupport.Profile? {
        profiles.first { $0.id == id }
    }

    func connectionSettingsChanged() {
        info = nil
        message = "接続設定が変わりました。接続を確認してください。"
    }

    func connect() async {
        guard !isWorking, let client = validatedClient() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let value = try await client.health()
            guard value.status == "ok", value.product == "SofTalk", value.bridgeVersion == 1 else {
                throw ValidationError.incompatibleBridge
            }
            info = value
            endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            tokenDraft = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(endpoint, forKey: Self.endpointKey)
            try KeychainStore.save(tokenDraft, account: Self.tokenAccount)
            let ready = value.profiles.filter(\.isConfigured).map(\.displayName)
            message = ready.isEmpty
                ? "接続しました。Windows側で霊夢・魔理沙の声を割り当ててください。"
                : "接続しました：\(ready.joined(separator: "、"))"
        } catch {
            info = nil
            message = error.localizedDescription
        }
    }

    func launch() async throws {
        guard let client = validatedClient() else { throw ValidationError.invalidConnection }
        try await client.launch()
        message = "Windows側でSofTalkを起動しました。"
    }

    func synthesize(text: String, profileID: String, settings: VoiceSettings) async throws -> Data {
        guard let client = validatedClient() else { throw ValidationError.invalidConnection }
        guard profile(id: profileID)?.isConfigured == true else {
            throw ValidationError.profileNotConfigured(SofTalkSupport.displayName(for: profileID))
        }
        return try await client.synthesize(.init(text: text, profileID: profileID, settings: settings))
    }

    private func validatedClient() -> SofTalkBridgeClient? {
        endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        tokenDraft = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: endpoint), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !tokenDraft.isEmpty else {
            message = ValidationError.invalidConnection.localizedDescription
            return nil
        }
        let localHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
        guard scheme == "https" || (scheme == "http" && localHosts.contains(host)) else {
            message = ValidationError.insecureRemote.localizedDescription
            return nil
        }
        return SofTalkBridgeClient(baseURL: url, token: tokenDraft)
    }

    enum ValidationError: LocalizedError {
        case invalidConnection
        case insecureRemote
        case incompatibleBridge
        case profileNotConfigured(String)

        var errorDescription: String? {
            switch self {
            case .invalidConnection: "接続先URLと接続トークンを入力してください。"
            case .insecureRemote: "別のPCへ接続する場合はHTTPSを使用してください。Tailscale ServeのURLを利用できます。"
            case .incompatibleBridge: "対応していないSofTalk連携先です。付属のブリッジを更新してください。"
            case .profileNotConfigured(let name): "Windows側で「\(name)」の声がまだ割り当てられていません。"
            }
        }
    }
}

enum SofTalkSynthesisService {
    struct SpeechResult: Sendable {
        var speech: SynthesizedSpeech
        var mouthKeyframes: [MouthKeyframe]
    }

    @MainActor
    static func speech(
        text: String,
        profileID: String,
        settings: VoiceSettings,
        mouthSpeed: Double
    ) async throws -> SpeechResult {
        let safeSettings = settings.validatedForSofTalk()
        let data = try await SofTalkConnectionController.shared.synthesize(
            text: text, profileID: profileID, settings: safeSettings
        )
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vms-softalk-analysis-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        let analysis = try ExternalVoiceImport.analyze(url: temporaryURL, mouthSpeed: mouthSpeed)
        return SpeechResult(
            speech: SynthesizedSpeech(audioData: data, moraTimings: [], duration: analysis.duration),
            mouthKeyframes: analysis.mouthKeyframes
        )
    }

    @MainActor
    static func importSpeech(
        text: String,
        profileID: String,
        settings: VoiceSettings,
        character: Character?,
        startTime: Double,
        assetsDirectory: URL
    ) async throws -> TTSImportResult {
        let safeSettings = settings.validatedForSofTalk()
        let data = try await SofTalkConnectionController.shared.synthesize(
            text: text, profileID: profileID, settings: safeSettings
        )
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vms-softalk-import-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)
        var result = try await ExternalVoiceImport.importFile(
            url: temporaryURL, text: text, provider: SofTalkSupport.providerID,
            characterID: character?.id, startTime: startTime,
            assetsDirectory: assetsDirectory, mouthSpeed: character?.defaultMouthSpeed ?? 1
        )
        if case .audio(var audio) = result.audioClip.content {
            audio.voiceLibrary = profileID
            audio.voiceStyle = SofTalkSupport.displayName(for: profileID)
            audio.voiceSettings = safeSettings
            audio.licenseNotes = character?.usageTerms ?? ""
            result.audioClip.content = .audio(audio)
        }
        if var clip = result.characterClip {
            clip.effects.flipHorizontal = character?.defaultFlipHorizontal ?? false
            result.characterClip = clip
        }
        return result
    }
}
