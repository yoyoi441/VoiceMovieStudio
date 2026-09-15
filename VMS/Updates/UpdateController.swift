import AppKit
import SwiftUI
import Sparkle
import VMSCore

struct AppVersion: Equatable, Sendable {
    let marketing: String
    let build: String

    static var current: AppVersion {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppVersion(
            marketing: info["CFBundleShortVersionString"] as? String ?? "不明",
            build: info["CFBundleVersion"] as? String ?? "不明"
        )
    }

    var displayText: String {
        marketing == build ? marketing : "\(marketing)（ビルド \(build)）"
    }
}

/// Sparkle handles background checks, signed downloads and installation on quit.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()
    private var controller: SPUStandardUpdaterController!
    weak var projectStore: ProjectStore?
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = true
    @Published private(set) var automaticDownloads = true
    @Published private(set) var statusMessage: String?

    private static var configuredFeedURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host?.lowercased() != "example.invalid" else { return nil }
        return url
    }

    var isFeedConfigured: Bool { Self.configuredFeedURL != nil }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.configuredFeedURL != nil,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticDownloads)
        if Self.configuredFeedURL == nil {
            automaticChecks = false
            automaticDownloads = false
            statusMessage = "この開発用ビルドには更新先が設定されていません。配布版から更新してください。"
        }
    }

    func check() {
        guard isFeedConfigured else {
            statusMessage = "この開発用ビルドには更新先が設定されていません。配布版から更新してください。"
            let alert = NSAlert()
            alert.messageText = "開発用ビルドでは更新できません"
            alert.informativeText = "現在起動している版は動作確認用で、更新フィードを持っていません。公開された配布版を最初に手動で導入すると、それ以降はアプリ内から更新できます。"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        statusMessage = "更新を確認しています…"
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard isFeedConfigured else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        guard isFeedConfigured else { return }
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        statusMessage = "更新を確認できませんでした：\(error.localizedDescription)"
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        guard let store = projectStore else { return true }
        do {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = support.appendingPathComponent("VMS/UpdateRecovery", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("\(UUID().uuidString).VMS", isDirectory: true)
            try ProjectPackage.write(project: store.project, assetsDirectory: store.assetsDirectory, to: target)
            UserDefaults.standard.set(target.path, forKey: "updates.pendingRecovery")
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "更新前の作業を保存できませんでした"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }
}

struct UpdateMenu: View {
    @ObservedObject var updater = UpdateController.shared
    var body: some View {
        Button("バージョンアップを確認…") { updater.check() }
            .disabled(updater.isFeedConfigured && !updater.canCheck)
        Toggle("更新を自動で確認", isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
            .disabled(!updater.isFeedConfigured)
        Toggle("更新を自動でダウンロード", isOn: Binding(get: { updater.automaticDownloads }, set: { updater.setAutomaticDownloads($0) }))
            .disabled(!updater.isFeedConfigured)
        Text("現在のバージョン：\(AppVersion.current.displayText)")
        if let message = updater.statusMessage { Text(message) }
        Text("開発版の更新を含みます")
    }
}

struct VersionManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var updater = UpdateController.shared
    private let version = AppVersion.current

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("バージョン管理").font(.title2).bold()
                    Text("ボイスムービースタジオ \(version.displayText)")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("更新チャンネル") {
                HStack {
                    Label("開発版（プレリリース）", systemImage: "wrench.and.screwdriver")
                    Spacer()
                    Text("機能が不安定な場合があります")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Toggle(
                "新しいバージョンを自動で確認",
                isOn: Binding(
                    get: { updater.automaticChecks },
                    set: { updater.setAutomaticChecks($0) }
                )
            )
            .disabled(!updater.isFeedConfigured)
            Toggle(
                "新しいバージョンを自動でダウンロード",
                isOn: Binding(
                    get: { updater.automaticDownloads },
                    set: { updater.setAutomaticDownloads($0) }
                )
            )
            .disabled(!updater.isFeedConfigured)

            if let message = updater.statusMessage {
                Label(message, systemImage: updater.isFeedConfigured ? "info.circle" : "hammer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("更新を適用する前に、開いている作業を復旧用プロジェクトとして保存します。更新後は自動的に開き直します。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("閉じる") { dismiss() }
                Spacer()
                Button {
                    updater.check()
                } label: {
                    Label("今すぐバージョンアップを確認", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(updater.isFeedConfigured && !updater.canCheck)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}
