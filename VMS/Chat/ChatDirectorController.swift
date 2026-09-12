import Foundation
import Observation
import VMSCore

@Observable
@MainActor
final class ChatDirectorController {
    static let apiKeyAccount = "openai-api-key"

    var draft = ""
    var pendingPlan: VideoEditPlan?
    var isWorking = false
    var progressText = ""
    var errorMessage: String?
    var isShowingSettings = false
    var apiKeyDraft = ""
    var model = UserDefaults.standard.string(forKey: "chatDirector.model") ?? "gpt-5.4-mini"

    var hasAPIKey: Bool { !(KeychainStore.read(account: Self.apiKeyAccount) ?? "").isEmpty }

    func openSettings() {
        apiKeyDraft = KeychainStore.read(account: Self.apiKeyAccount) ?? ""
        isShowingSettings = true
    }

    func saveSettings() {
        do {
            let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { KeychainStore.delete(account: Self.apiKeyAccount) }
            else { try KeychainStore.save(trimmed, account: Self.apiKeyAccount) }
            UserDefaults.standard.set(model, forKey: "chatDirector.model")
            isShowingSettings = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(store: ProjectStore) async {
        let instruction = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        let assets = store.project.mediaAssets.filter { $0.kind == .video }
        guard !assets.isEmpty else {
            errorMessage = "先に動画素材を追加してください。"
            return
        }
        draft = ""
        isWorking = true
        errorMessage = nil
        store.appendChatMessage(role: .user, text: instruction)
        defer { isWorking = false; progressText = "" }

        progressText = "動画の代表フレームを解析中…"
        let directory = store.assetsDirectory
        let analyzed = await withTaskGroup(of: AnalyzedVideoMaterial.self) { group in
            for asset in assets.prefix(8) {
                group.addTask { await VideoMaterialAnalyzer.analyze(asset, assetsDirectory: directory) }
            }
            var result: [AnalyzedVideoMaterial] = []
            for await item in group { result.append(item) }
            return result.sorted { $0.asset.originalName < $1.asset.originalName }
        }

        do {
            let key = KeychainStore.read(account: Self.apiKeyAccount) ?? ""
            let director: any ChatDirector = key.isEmpty
                ? LocalChatDirector()
                : OpenAIChatDirector(apiKey: key, model: model)
            progressText = key.isEmpty ? "簡易編集案を作成中…" : "AIが編集案を作成中…"
            let plan = try await director.createPlan(
                instruction: instruction,
                materials: analyzed,
                history: store.project.chatMessages
            )
            let validated = try plan.validated(against: assets)
            pendingPlan = validated
            store.appendChatMessage(role: .assistant, text: "\(validated.summary)\n\(validated.segments.count)カットの編集案を作成しました。")
        } catch {
            errorMessage = error.localizedDescription
            store.appendChatMessage(role: .system, text: "エラー: \(error.localizedDescription)")
        }
    }

    func apply(store: ProjectStore) {
        guard let pendingPlan else { return }
        do {
            try store.applyVideoEditPlan(pendingPlan)
            store.appendChatMessage(role: .assistant, text: "編集案をタイムラインへ反映しました。「取り消し」で元に戻せます。")
            self.pendingPlan = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
