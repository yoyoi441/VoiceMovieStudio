import AppKit
import Foundation
import UniformTypeIdentifiers
import VMSCore

@MainActor
enum AquesTalkPlayerSettings {
    static let applicationPathKey = "aquesTalkPlayerApplicationPath"
    static let licenseAcknowledgedKey = "aquesTalkPlayerLicenseNoticeAcknowledged"
    static let publicLicenseIDKey = "aquesTalkPlayerPublicLicenseID"

    static var licenseAcknowledged: Bool {
        UserDefaults.standard.bool(forKey: licenseAcknowledgedKey)
    }
}

struct AquesTalkPlayerInstallation: Sendable, Equatable {
    var applicationURL: URL
    var executableURL: URL
    var bundleIdentifier: String
    var version: String
}

enum AquesTalkPlayerError: Error, LocalizedError {
    case notInstalled
    case invalidApplication
    case licenseNotAcknowledged
    case emptyText
    case launchFailed(String)
    case generationFailed(String)
    case generationTimedOut
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "AquesTalk Playerが見つかりません。公式サイトからMac版をインストールするか、アプリを選択してください。"
        case .invalidApplication:
            "選択したアプリはAquesTalk Playerとして確認できませんでした。"
        case .licenseNotAcknowledged:
            "利用条件を確認してから生成してください。商用利用などには使用ライセンスが必要です。"
        case .emptyText:
            "セリフを入力してください。"
        case .launchFailed(let detail):
            "AquesTalk Playerを起動できませんでした。\(detail)"
        case .generationFailed(let detail):
            "AquesTalk Playerで音声を生成できませんでした。\(detail)"
        case .generationTimedOut:
            "AquesTalk Playerの音声生成が時間内に完了しませんでした。アプリ側の表示とライセンス設定を確認してください。"
        case .emptyAudio:
            "AquesTalk Playerが有効なWAVを出力しませんでした。プリセット名とライセンス設定を確認してください。"
        }
    }
}

@MainActor
enum AquesTalkPlayerService {
    struct SpeechResult: Sendable {
        var speech: SynthesizedSpeech
        var mouthKeyframes: [MouthKeyframe]
    }

    static func installation() -> AquesTalkPlayerInstallation? {
        let defaults = UserDefaults.standard.string(forKey: AquesTalkPlayerSettings.applicationPathKey)
            .map(URL.init(fileURLWithPath:))
        let candidates = [
            defaults,
            URL(fileURLWithPath: "/Applications/AquesTalkPlayer.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/AquesTalkPlayer.app")
        ].compactMap { $0 }
        return candidates.lazy.compactMap(validatedInstallation(at:)).first
    }

    static var isReady: Bool {
        installation() != nil && AquesTalkPlayerSettings.licenseAcknowledged
    }

    static func selectApplication() -> AquesTalkPlayerInstallation? {
        let panel = NSOpenPanel()
        panel.title = "AquesTalk Playerを選択"
        panel.prompt = "選択"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let selected = validatedInstallation(at: url) else { return nil }
        UserDefaults.standard.set(url.path, forKey: AquesTalkPlayerSettings.applicationPathKey)
        return selected
    }

    static func launch() async throws {
        guard let found = installation() else { throw AquesTalkPlayerError.notInstalled }

        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: found.bundleIdentifier)
            .first(where: { !$0.isTerminated }) {
            guard running.activate(options: [.activateAllWindows]) else {
                throw AquesTalkPlayerError.launchFailed("起動中のアプリを前面に表示できませんでした。")
            }
            return
        }

        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await NSWorkspace.shared.openApplication(
                at: found.applicationURL,
                configuration: configuration
            )
        } catch {
            throw AquesTalkPlayerError.launchFailed(error.localizedDescription)
        }
    }

    static func speech(
        text: String,
        presetName: String,
        mouthSpeed: Double
    ) async throws -> SpeechResult {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { throw AquesTalkPlayerError.emptyText }
        guard AquesTalkPlayerSettings.licenseAcknowledged else {
            throw AquesTalkPlayerError.licenseNotAcknowledged
        }
        guard let found = installation() else { throw AquesTalkPlayerError.notInstalled }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceMovieStudio-AquesTalkPlayer", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let wavURL = temporaryDirectory.appendingPathComponent("speech.wav")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let arguments = AquesTalkPlayerSupport.commandArguments(
            text: normalizedText,
            presetName: presetName,
            wavPath: wavURL.path
        )
        try await run(executableURL: found.executableURL, arguments: arguments)
        guard FileManager.default.fileExists(atPath: wavURL.path) else {
            throw AquesTalkPlayerError.emptyAudio
        }
        let data = try Data(contentsOf: wavURL)
        guard data.count >= 12,
              data.prefix(4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WAVE".utf8) else {
            throw AquesTalkPlayerError.emptyAudio
        }
        let analysis = try ExternalVoiceImport.analyze(url: wavURL, mouthSpeed: mouthSpeed)
        return SpeechResult(
            speech: SynthesizedSpeech(audioData: data, moraTimings: [], duration: analysis.duration),
            mouthKeyframes: analysis.mouthKeyframes
        )
    }

    static func importSpeech(
        text: String,
        presetName: String,
        character: Character?,
        startTime: Double,
        assetsDirectory: URL
    ) async throws -> TTSImportResult {
        let generated = try await speech(
            text: text,
            presetName: presetName,
            mouthSpeed: character?.defaultMouthSpeed ?? 1
        )
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-movie-studio-aquestalk-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try generated.speech.audioData.write(to: temporaryURL, options: .atomic)
        var result = try await ExternalVoiceImport.importFile(
            url: temporaryURL,
            text: text,
            provider: AquesTalkPlayerSupport.providerID,
            characterID: character?.id,
            startTime: startTime,
            assetsDirectory: assetsDirectory,
            mouthSpeed: character?.defaultMouthSpeed ?? 1
        )
        if case .audio(var audio) = result.audioClip.content {
            audio.voiceLibrary = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
            audio.voiceStyle = ""
            audio.voiceSettings = VoiceSettings()
            audio.licenseNotes = [
                AquesTalkPlayerSupport.commercialUseNotice,
                character?.usageTerms ?? ""
            ].filter { !$0.isEmpty }.joined(separator: "\n")
            result.audioClip.content = .audio(audio)
        }
        if var clip = result.characterClip {
            clip.effects.flipHorizontal = character?.defaultFlipHorizontal ?? false
            result.characterClip = clip
        }
        return result
    }

    private static func validatedInstallation(at applicationURL: URL) -> AquesTalkPlayerInstallation? {
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        guard let dictionary = NSDictionary(contentsOf: infoURL),
              let executable = dictionary["CFBundleExecutable"] as? String,
              let bundleIdentifier = dictionary["CFBundleIdentifier"] as? String,
              bundleIdentifier == AquesTalkPlayerSupport.bundleIdentifier else { return nil }
        let displayName = (dictionary["CFBundleDisplayName"] as? String)
            ?? (dictionary["CFBundleName"] as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        guard displayName.localizedCaseInsensitiveContains("AquesTalkPlayer")
                || applicationURL.lastPathComponent.localizedCaseInsensitiveContains("AquesTalkPlayer") else {
            return nil
        }
        let executableURL = applicationURL.appendingPathComponent("Contents/MacOS/\(executable)")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { return nil }
        return AquesTalkPlayerInstallation(
            applicationURL: applicationURL,
            executableURL: executableURL,
            bundleIdentifier: bundleIdentifier,
            version: (dictionary["CFBundleShortVersionString"] as? String) ?? "不明"
        )
    }

    nonisolated private static func run(executableURL: URL, arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = executableURL
            process.currentDirectoryURL = executableURL.deletingLastPathComponent()
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe
            do { try process.run() }
            catch { throw AquesTalkPlayerError.generationFailed(error.localizedDescription) }

            let deadline = ContinuousClock.now + .seconds(90)
            while process.isRunning {
                if Task.isCancelled {
                    process.terminate()
                    throw CancellationError()
                }
                if ContinuousClock.now >= deadline {
                    process.terminate()
                    throw AquesTalkPlayerError.generationTimedOut
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw AquesTalkPlayerError.generationFailed(
                    detail?.isEmpty == false ? detail! : "終了コード \(process.terminationStatus)"
                )
            }
        }.value
    }
}
