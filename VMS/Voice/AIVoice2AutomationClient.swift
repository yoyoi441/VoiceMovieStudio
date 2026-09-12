import AppKit
import ApplicationServices
import VMSCore

/// Drives only accessibility elements explicitly exposed by A.I.VOICE2. No OCR,
/// private engine API, fixed coordinates, or voice-name guessing is used.
@MainActor
final class AIVoice2AutomationClient {
    struct Request {
        var text: String
        var speakerName: String
        var settings: VoiceSettings
    }

    struct ExportedFile {
        var wavURL: URL
        var temporaryDirectory: URL

        func removeTemporaryFiles() {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    enum Failure: Error, LocalizedError {
        case accessibilityPermission
        case applicationUnavailable
        case missingControl(String)
        case ambiguousControl(String)
        case valueRejected(String)
        case exportDialog
        case exportTimedOut

        var errorDescription: String? {
            switch self {
            case .accessibilityPermission:
                "直接生成には、システム設定の「プライバシーとセキュリティ → アクセシビリティ」でボイスムービースタジオを許可してください。"
            case .applicationUnavailable:
                "A.I.VOICE2の編集画面を確認できませんでした。起動とライセンス認証を確認してください。"
            case .missingControl(let name):
                "A.I.VOICE2が「\(name)」を操作可能な項目として公開していません。画面を閉じず、テキスト編集画面を表示して再試行してください。"
            case .ambiguousControl(let name):
                "A.I.VOICE2内に「\(name)」が複数あり、安全に特定できないため停止しました。"
            case .valueRejected(let name):
                "A.I.VOICE2が「\(name)」の設定値を受け付けませんでした。"
            case .exportDialog:
                "音声の保存先を自動設定できませんでした。A.I.VOICE2の書き出し画面を閉じて再試行してください。"
            case .exportTimedOut:
                "音声ファイルの生成を時間内に確認できませんでした。製品側にエラー表示がないか確認してください。"
            }
        }
    }

    private let bundleIdentifier = "jp.ai-j.AIVoice2"
    private var didRequestAccessibilityPrompt = false

    func audition(_ request: Request) async throws {
        let context = try await prepare(request)
        guard pressButton(in: context.appElement, titles: ["再生", "試聴"]) else {
            throw Failure.missingControl("再生")
        }
    }

    func synthesize(_ request: Request) async throws -> ExportedFile {
        let context = try await prepare(request)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceMovieStudio-AIVoice2", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        do {
            guard pressButton(in: context.appElement, titles: ["書き出し", "音声ファイルを作る"]) else {
                throw Failure.missingControl("書き出し")
            }
            try await chooseExportDirectory(
                temporaryDirectory, runningApplication: context.runningApplication,
                appElement: context.appElement
            )
            let wav = try await waitForExport(in: temporaryDirectory)
            return ExportedFile(wavURL: wav, temporaryDirectory: temporaryDirectory)
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private struct Context {
        var runningApplication: NSRunningApplication
        var appElement: AXUIElement
    }

    private func prepare(_ request: Request) async throws -> Context {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.valueRejected("セリフ") }
        guard !request.speakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.valueRejected("話者")
        }
        guard accessibilityPermission(promptIfNeeded: true) else {
            throw Failure.accessibilityPermission
        }

        try await AIVoice2Launcher.launch()
        guard let running = try await waitForApplication() else { throw Failure.applicationUnavailable }
        running.activate()
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        guard try await waitUntil({ !self.elements(app, kAXWindowsAttribute).isEmpty }, seconds: 20) else {
            throw Failure.applicationUnavailable
        }

        try selectSpeaker(request.speakerName, in: app)
        try setDialogue(text, in: app)
        try? await Task.sleep(for: .milliseconds(450))

        let settings = request.settings.validatedForAIVoice2()
        try set(parameter: .volume, value: settings.volume, in: app)
        try set(parameter: .speed, value: settings.speed, in: app)
        try set(parameter: .pitch, value: settings.pitch, in: app)
        try set(parameter: .intonation, value: settings.intonation, in: app)

        if let weights = settings.styleWeights {
            for (name, value) in weights.sorted(by: { $0.key < $1.key }) {
                try setLabeledNumericControl(label: name, value: min(1, max(0, value)), in: app)
            }
        }
        return Context(runningApplication: running, appElement: app)
    }

    private func waitForApplication() async throws -> NSRunningApplication? {
        for _ in 0..<80 {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                return running
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    private func accessibilityPermission(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        guard promptIfNeeded, !didRequestAccessibilityPrompt else { return false }
        didRequestAccessibilityPrompt = true
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func selectSpeaker(_ name: String, in app: AXUIElement) throws {
        let normalizedName = normalize(name)
        let candidates = allElements(in: app).filter { element in
            let role = string(element, kAXRoleAttribute)
            guard [kAXRowRole, kAXButtonRole, kAXRadioButtonRole].contains(role) else { return false }
            return semanticStrings(element, depth: 2).contains { normalize($0) == normalizedName }
        }
        let preferred = [kAXRowRole, kAXRadioButtonRole, kAXButtonRole]
            .compactMap { role in
                let matches = candidates.filter { string($0, kAXRoleAttribute) == role }
                return matches.count == 1 ? matches[0] : nil
            }.first
        guard let target = preferred else {
            if candidates.isEmpty { throw Failure.missingControl("話者「\(name)」") }
            throw Failure.ambiguousControl("話者「\(name)」")
        }
        if setBoolean(true, on: target, attribute: kAXSelectedAttribute) { return }
        guard AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
            throw Failure.valueRejected("話者「\(name)」")
        }
    }

    private func setDialogue(_ text: String, in app: AXUIElement) throws {
        let candidates = allElements(in: app).filter { element in
            let role = string(element, kAXRoleAttribute)
            guard role == kAXTextAreaRole || role == kAXTextFieldRole,
                  isSettable(element, kAXValueAttribute) else { return false }
            let labels = semanticStrings(element, depth: 1).map(normalize)
            let labelled = labels.contains { value in
                ["セリフ", "テキスト", "文章", "本文", "読み上げ内容"].contains { value.contains($0) }
            }
            let current = string(element, kAXValueAttribute)
            return labelled || (role == kAXTextAreaRole && Double(current) == nil)
        }
        let explicitlyLabelled = candidates.filter { element in
            semanticStrings(element, depth: 1).map(normalize).contains { value in
                ["セリフ", "テキスト", "文章", "本文", "読み上げ内容"].contains { value.contains($0) }
            }
        }
        let textAreas = candidates.filter { string($0, kAXRoleAttribute) == kAXTextAreaRole }
        let target: AXUIElement
        if explicitlyLabelled.count == 1 { target = explicitlyLabelled[0] }
        else if textAreas.count == 1 { target = textAreas[0] }
        else if candidates.isEmpty { throw Failure.missingControl("セリフ入力") }
        else { throw Failure.ambiguousControl("セリフ入力") }
        guard AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, text as CFTypeRef) == .success,
              string(target, kAXValueAttribute) == text else {
            throw Failure.valueRejected("セリフ")
        }
    }

    private func set(parameter: AIVoice2Parameter, value: Double, in app: AXUIElement) throws {
        try setLabeledNumericControl(label: parameter.label, value: parameter.clamp(value), in: app)
    }

    private func setLabeledNumericControl(label: String, value: Double, in app: AXUIElement) throws {
        let targetLabel = normalize(label)
        let candidates = allElements(in: app).filter { element in
            let role = string(element, kAXRoleAttribute)
            guard (role == kAXSliderRole || role == kAXTextFieldRole),
                  isSettable(element, kAXValueAttribute) else { return false }
            return semanticStrings(element, depth: 0).contains { normalize($0).contains(targetLabel) }
                || ancestor(upFrom: element, levels: 2).contains { ancestor in
                    semanticStrings(ancestor, depth: 1).contains { normalize($0) == targetLabel }
                }
        }
        let sliders = candidates.filter { string($0, kAXRoleAttribute) == kAXSliderRole }
        let usable = sliders.isEmpty ? candidates : sliders
        guard !usable.isEmpty else { throw Failure.missingControl(label) }
        guard usable.count == 1 else { throw Failure.ambiguousControl(label) }
        let control = usable[0]
        let number = NSNumber(value: value)
        guard AXUIElementSetAttributeValue(control, kAXValueAttribute as CFString, number) == .success else {
            throw Failure.valueRejected(label)
        }
        guard let actual = numericValue(control), abs(actual - value) <= 0.011 else {
            throw Failure.valueRejected(label)
        }
    }

    private func chooseExportDirectory(
        _ directory: URL,
        runningApplication: NSRunningApplication,
        appElement: AXUIElement
    ) async throws {
        try? await Task.sleep(for: .milliseconds(350))
        runningApplication.activate()
        postHotKey(keyCode: 5, modifiers: [.maskCommand, .maskShift], to: runningApplication.processIdentifier)

        guard try await waitUntil({
            self.allElements(in: appElement).contains {
                let role = self.string($0, kAXRoleAttribute)
                return (role == kAXTextFieldRole || role == kAXTextAreaRole)
                    && self.isSettable($0, kAXValueAttribute)
                    && (self.bool($0, kAXFocusedAttribute) || self.semanticStrings($0, depth: 1).contains { self.normalize($0).contains("フォルダ") })
            }
        }, seconds: 5) else { throw Failure.exportDialog }

        let fields = allElements(in: appElement).filter {
            let role = string($0, kAXRoleAttribute)
            return (role == kAXTextFieldRole || role == kAXTextAreaRole)
                && isSettable($0, kAXValueAttribute)
                && (bool($0, kAXFocusedAttribute) || semanticStrings($0, depth: 1).contains { normalize($0).contains("フォルダ") })
        }
        let field = fields.first(where: { bool($0, kAXFocusedAttribute) }) ?? fields.first
        guard let field,
              AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, directory.path as CFTypeRef) == .success,
              pressButton(in: appElement, titles: ["移動"]) else {
            throw Failure.exportDialog
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard pressButton(in: appElement, titles: ["開く", "選択", "保存", "書き出し"]) else {
            throw Failure.exportDialog
        }
    }

    private func waitForExport(in directory: URL) async throws -> URL {
        var previousSize: Int?
        var previousURL: URL?
        for _ in 0..<240 {
            try Task.checkCancellation()
            let wavs = recursiveWAVs(in: directory)
            if let url = wavs.max(by: { modificationDate($0) < modificationDate($1) }),
               let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > 44 {
                if previousURL == url, previousSize == size { return url }
                previousURL = url
                previousSize = size
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw Failure.exportTimedOut
    }

    private func recursiveWAVs(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "wav" }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func pressButton(in root: AXUIElement, titles: [String]) -> Bool {
        for title in titles {
            let normalized = normalize(title)
            for role in [kAXButtonRole, kAXMenuItemRole] {
                let matches = allElements(in: root).filter { element in
                    guard string(element, kAXRoleAttribute) == role else { return false }
                    return semanticStrings(element, depth: 1).contains { normalize($0) == normalized }
                        && bool(element, kAXEnabledAttribute, fallback: true)
                }
                if matches.count == 1,
                   AXUIElementPerformAction(matches[0], kAXPressAction as CFString) == .success { return true }
            }
        }
        return false
    }

    private func postHotKey(keyCode: CGKeyCode, modifiers: CGEventFlags, to pid: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = modifiers
        up.flags = modifiers
        down.postToPid(pid)
        up.postToPid(pid)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool, seconds: Double) async throws -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try Task.checkCancellation()
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    private func allElements(in root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var budget = 1_500
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 24, budget > 0 else { return }
            budget -= 1
            result.append(element)
            for child in elements(element, kAXChildrenAttribute) { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return result
    }

    private func semanticStrings(_ element: AXUIElement, depth: Int) -> [String] {
        var result = [
            string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute),
            string(element, kAXHelpAttribute), string(element, kAXIdentifierAttribute)
        ].filter { !$0.isEmpty }
        if depth > 0 {
            for child in elements(element, kAXChildrenAttribute) {
                result += semanticStrings(child, depth: depth - 1)
            }
        }
        return result
    }

    private func ancestor(upFrom element: AXUIElement, levels: Int) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var current = element
        for _ in 0..<levels {
            guard let rawParent = attribute(current, kAXParentAttribute) else { break }
            let parent = rawParent as! AXUIElement
            result.append(parent)
            current = parent
        }
        return result
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.widthInsensitive, .caseInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private func setBoolean(_ value: Bool, on element: AXUIElement, attribute name: String) -> Bool {
        guard isSettable(element, name),
              AXUIElementSetAttributeValue(element, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse) == .success else { return false }
        return bool(element, name) == value
    }

    private func numericValue(_ element: AXUIElement) -> Double? {
        if let number = attribute(element, kAXValueAttribute) as? NSNumber { return number.doubleValue }
        return Double(string(element, kAXValueAttribute))
    }

    private func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private func bool(_ element: AXUIElement, _ name: String, fallback: Bool = false) -> Bool {
        (attribute(element, name) as? Bool) ?? fallback
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String {
        if let text = attribute(element, name) as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }
}
