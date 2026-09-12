import AppKit

/// Launches the VOICEVOX editor app so the user doesn't have to switch away from
/// VMS to start it themselves before generating voice.
enum VoiceVoxLauncher {
    enum LaunchError: Error, LocalizedError {
        case notFound

        var errorDescription: String? {
            "VOICEVOXアプリが見つかりませんでした。https://voicevox.hiho.jp/ からインストールしてください。"
        }
    }

    // VOICEVOX's actual bundle identifier isn't guaranteed to match across releases, so
    // this tries a couple of known candidates, then falls back to the standard install
    // locations (a plain .app bundle doesn't need a matching bundle identifier to open).
    private static let bundleIdentifiers = [
        "jp.hiroshiba.voicevox",
        "jp.hiroshiba.voicevox-editor"
    ]
    private static let knownPaths = [
        "/Applications/VOICEVOX.app",
        "\(NSHomeDirectory())/Applications/VOICEVOX.app"
    ]

    static func launch() throws {
        if let url = bundleIdentifiers.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
            NSWorkspace.shared.open(url)
            return
        }
        if let path = knownPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        throw LaunchError.notFound
    }
}
