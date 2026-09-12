@preconcurrency import AVFoundation
import Foundation
import Observation
import VMSCore

enum AIExecutionLocation: String, CaseIterable, Identifiable {
    case local
    case remote

    var id: String { rawValue }
    var title: String { self == .local ? "このMac" : "リモートMac" }
    var symbol: String { self == .local ? "desktopcomputer" : "network" }
    var defaultEndpoint: String { self == .local ? "http://127.0.0.1:8765" : "" }
    var endpointKey: String { "aiNode.\(rawValue).endpoint" }
    var modelKey: String { "aiNode.\(rawValue).model" }
    var tokenAccount: String { "\(rawValue)-ai-node-token" }
}

@Observable
@MainActor
final class RemoteAIController {
    private struct ConnectionDraft {
        var endpoint: String
        var token: String
        var model: String
    }

    private static let legacyRemoteEndpointKey = "remoteAI.endpoint"
    private static let legacyRemoteTokenAccount = "remote-ai-node-token"
    var location: AIExecutionLocation = .remote
    var endpoint = ""
    var tokenDraft = ""
    var node: RemoteAINodeInfo?
    var selectedAssetID: UUID?
    var language = "ja"
    var instruction = "重要な発言と結論を中心に、クリップ候補を作ってください"
    var selectedModel = ""
    var job: RemoteAIJobStatus?
    var analysis: RemoteAIAnalysis?
    var isWorking = false
    var errorMessage: String?
    private var pollTask: Task<Void, Never>?
    private var drafts: [AIExecutionLocation: ConnectionDraft] = [:]

    init() {
        Self.importBootstrapTokenIfNeeded()
        Self.migrateLegacyRemoteProfileIfNeeded()
        location = AIExecutionLocation(
            rawValue: UserDefaults.standard.string(forKey: "aiNode.location") ?? ""
        ) ?? .remote
        for value in AIExecutionLocation.allCases {
            drafts[value] = ConnectionDraft(
                endpoint: UserDefaults.standard.string(forKey: value.endpointKey) ?? value.defaultEndpoint,
                token: KeychainStore.read(account: value.tokenAccount) ?? "",
                model: UserDefaults.standard.string(forKey: value.modelKey) ?? ""
            )
        }
        loadDraft(for: location)
    }

    static func importBootstrapTokenIfNeeded() {
        guard KeychainStore.read(account: AIExecutionLocation.remote.tokenAccount) == nil else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bootstrap = support.appendingPathComponent("VMS/RemoteAI/bootstrap-token")
        if let value = try? String(contentsOf: bootstrap, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            if (try? KeychainStore.save(value, account: AIExecutionLocation.remote.tokenAccount)) != nil {
                try? FileManager.default.removeItem(at: bootstrap)
            }
        }
    }

    private static func migrateLegacyRemoteProfileIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: AIExecutionLocation.remote.endpointKey) == nil,
           let legacy = defaults.string(forKey: legacyRemoteEndpointKey), !legacy.isEmpty {
            defaults.set(legacy, forKey: AIExecutionLocation.remote.endpointKey)
        }
        if KeychainStore.read(account: AIExecutionLocation.remote.tokenAccount) == nil,
           let legacy = KeychainStore.read(account: legacyRemoteTokenAccount), !legacy.isEmpty {
            try? KeychainStore.save(legacy, account: AIExecutionLocation.remote.tokenAccount)
        }
    }

    func selectLocation(_ newValue: AIExecutionLocation) {
        guard newValue != location, !isWorking else { return }
        drafts[location] = ConnectionDraft(
            endpoint: endpoint, token: tokenDraft, model: selectedModel
        )
        location = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: "aiNode.location")
        loadDraft(for: newValue)
        node = nil
        job = nil
        errorMessage = nil
    }

    func restoreDefaultLocalEndpoint() {
        guard location == .local, !isWorking else { return }
        endpoint = AIExecutionLocation.local.defaultEndpoint
        node = nil
    }

    func connectionSettingsChanged() {
        guard !isWorking else { return }
        node = nil
        job = nil
    }

    func saveSelectedModel() {
        guard !selectedModel.isEmpty else { return }
        UserDefaults.standard.set(selectedModel, forKey: location.modelKey)
        if var draft = drafts[location] {
            draft.model = selectedModel
            drafts[location] = draft
        }
    }

    var client: RemoteAIClient? {
        guard let url = URL(string: endpoint), !tokenDraft.isEmpty else { return nil }
        return RemoteAIClient(baseURL: url, token: tokenDraft)
    }

    func connect() async {
        endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        tokenDraft = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateCurrentConnection(), let client else { return }
        isWorking = true; errorMessage = nil
        do {
            node = try await client.health()
            UserDefaults.standard.set(endpoint, forKey: location.endpointKey)
            try KeychainStore.save(tokenDraft, account: location.tokenAccount)
            if selectedModel.isEmpty || node?.models.contains(selectedModel) != true {
                selectedModel = node?.models.first ?? ""
            }
            UserDefaults.standard.set(selectedModel, forKey: location.modelKey)
            drafts[location] = ConnectionDraft(
                endpoint: endpoint, token: tokenDraft, model: selectedModel
            )
        } catch { errorMessage = error.localizedDescription; node = nil }
        isWorking = false
    }

    private func loadDraft(for value: AIExecutionLocation) {
        let draft = drafts[value] ?? ConnectionDraft(
            endpoint: value.defaultEndpoint, token: "", model: ""
        )
        endpoint = draft.endpoint
        tokenDraft = draft.token
        selectedModel = draft.model
    }

    private func validateCurrentConnection() -> Bool {
        guard let url = URL(string: endpoint), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !tokenDraft.isEmpty else {
            errorMessage = "接続先URLと接続トークンを入力してください。"
            return false
        }
        if location == .local {
            let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
            guard loopbackHosts.contains(host), scheme == "http" || scheme == "https" else {
                errorMessage = "「このMac」では127.0.0.1、localhost、または::1の接続先だけを使用できます。"
                return false
            }
        } else if scheme != "https" {
            errorMessage = "リモートMacへの接続にはHTTPSを使用してください。Tailscale ServeのURLを指定します。"
            return false
        }
        return true
    }

    func transcribe(store: ProjectStore) async {
        guard let asset = store.project.mediaAssets.first(where: { $0.id == selectedAssetID }), asset.kind == .video || asset.kind == .audio,
              let client else { errorMessage = "動画または音声素材と接続済みAIノードを選択してください。"; return }
        isWorking = true; errorMessage = nil
        do {
            let source = store.assetsDirectory.appendingPathComponent(asset.fileName)
            let audio = try await Self.exportAudio(from: source)
            defer { try? FileManager.default.removeItem(at: audio) }
            let submitted = try await client.submitTranscription(fileURL: audio, language: language)
            job = submitted
            try await poll(id: submitted.id, client: client)
            if let transcript = job?.transcript {
                analysis = RemoteAIAnalysis(assetID: asset.id, language: language, transcript: transcript)
                saveAnalysis(store: store)
            }
        } catch { errorMessage = error.localizedDescription }
        isWorking = false
    }

    func analyzeHighlights(store: ProjectStore) async {
        guard let analysis, !analysis.transcript.isEmpty, let client else { errorMessage = "先に文字起こしを実行してください。"; return }
        isWorking = true; errorMessage = nil
        do {
            let submitted = try await client.submitHighlights(transcript: analysis.transcript, instruction: instruction, model: selectedModel.isEmpty ? nil : selectedModel)
            job = submitted
            try await poll(id: submitted.id, client: client)
            self.analysis?.highlights = job?.highlights ?? []
            self.analysis?.summary = job?.summary ?? ""
            saveAnalysis(store: store)
        } catch { errorMessage = error.localizedDescription }
        isWorking = false
    }

    func recommendStoryboard(
        lines: [ScenarioDraftLine],
        characters: [Character],
        instruction: String
    ) async -> ScenarioAIPlan? {
        if node == nil {
            await connect()
        }
        guard node?.capabilities.contains(.clipPlanning) == true, let client else {
            if errorMessage == nil {
                errorMessage = "選択中のAIノードはシナリオ配置に対応していません。AI設定で接続を確認してください。"
            }
            return nil
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let submitted = try await client.submitStoryboardPlan(
                lines: lines,
                characters: characters,
                instruction: instruction,
                model: selectedModel.isEmpty ? nil : selectedModel
            )
            job = submitted
            try await poll(id: submitted.id, client: client)
            guard let plan = job?.storyboardPlan else {
                throw RemoteError.jobFailed("AIノードから配置案を受け取れませんでした。")
            }
            return plan
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func cancel() {
        guard let id = job?.id, let client else { return }
        pollTask?.cancel()
        Task { try? await client.cancel(id: id) }
        isWorking = false
    }

    private func poll(id: UUID, client: RemoteAIClient) async throws {
        while !Task.isCancelled {
            let current = try await client.status(id: id)
            job = current
            switch current.state {
            case .completed: return
            case .failed: throw RemoteError.jobFailed(current.error ?? current.message)
            case .cancelled: throw CancellationError()
            default: try await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func saveAnalysis(store: ProjectStore) {
        guard let analysis else { return }
        if let index = store.project.aiAnalyses.firstIndex(where: { $0.id == analysis.id }) { store.project.aiAnalyses[index] = analysis }
        else { store.project.aiAnalyses.append(analysis) }
    }

    static func exportAudio(from source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("ai_audio_\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw RemoteError.audioExport }
        let box = ExportSessionBox(exporter)
        return try await withCheckedThrowingContinuation { continuation in
            exporter.outputURL = output
            exporter.outputFileType = .m4a
            exporter.exportAsynchronously {
                switch box.session.status {
                case .completed: continuation.resume(returning: output)
                case .failed, .cancelled: continuation.resume(throwing: box.session.error ?? RemoteError.audioExport)
                default: continuation.resume(throwing: RemoteError.audioExport)
                }
            }
        }
    }

    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }

    enum RemoteError: LocalizedError {
        case audioExport, jobFailed(String)
        var errorDescription: String? {
            switch self { case .audioExport: return "解析用音声を作成できませんでした。"; case .jobFailed(let value): return value }
        }
    }
}
