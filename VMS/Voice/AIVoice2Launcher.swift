import AppKit
import UniformTypeIdentifiers

@MainActor
enum AIVoice2Launcher {
    private static let bookmarkKey = "aivoice2.applicationBookmark"
    // Verified on the portable Mac: A.I.VOICE2 2.14.1.
    private static let bundleIdentifier = "jp.ai-j.AIVoice2"

    static func launch(selectAgain: Bool = false) async throws {
        var stale = false
        var url: URL?
        if !selectAgain, let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                           relativeTo: nil, bookmarkDataIsStale: &stale)
        }
        if !selectAgain && (url == nil || stale || url.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true) {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            if url == nil {
                let standard = URL(fileURLWithPath: "/Applications/AIVoice2.app")
                if Bundle(url: standard)?.bundleIdentifier == bundleIdentifier { url = standard }
            }
            stale = false
        }
        if url == nil || stale || url.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true {
            let panel = NSOpenPanel()
            panel.title = "インストールしたA.I.VOICE2アプリを選択"
            panel.allowedContentTypes = [.application]
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            url = selected
        }
        guard let url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bundle = Bundle(url: url) else { throw Failure.wrongApplication }
        let names = [bundle.bundleIdentifier ?? "", url.deletingPathExtension().lastPathComponent,
                     bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""]
        let matches = names.contains {
            $0.lowercased().filter { $0.isLetter || $0.isNumber }.contains("aivoice2")
        }
        guard matches else { throw Failure.wrongApplication }
        let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                           includingResourceValuesForKeys: nil, relativeTo: nil)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    enum Failure: Error, LocalizedError {
        case wrongApplication
        var errorDescription: String? {
            "A.I.VOICE2として確認できるアプリを選択してください。インストーラーや別のアプリは起動しません。"
        }
    }
}
