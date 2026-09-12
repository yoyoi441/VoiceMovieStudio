import AppKit
import ApplicationServices
import Observation

/// Conservative UI adapter: only named rows inside an explicitly labelled character list.
/// Unlabelled/custom-drawn views are unsupported; no OCR/coordinate guesses or private APIs.
@Observable @MainActor
final class AIVoice2Catalog {
    private(set) var names: [String] = []
    private(set) var styleNames: [String] = []
    private(set) var status = "話者一覧はまだ読み取っていません。"
    private(set) var isBusy = false
    private var didRequestAccessibilityPrompt = false

    func launchAndRead(preferredName: String?) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard accessibilityPermission(promptIfNeeded: true) else {
            status = permissionMessage
            return
        }
        do {
            try await AIVoice2Launcher.launch()
            // A launched process can appear before its accessibility window is ready.
            for attempt in 0..<3 {
                if refresh(preferredName: preferredName) { return }
                if !AXIsProcessTrusted() { return }
                if attempt < 2 { try await Task.sleep(for: .seconds(1)) }
            }
        } catch { status = error.localizedDescription }
    }

    @discardableResult
    func refresh(preferredName: String? = nil) -> Bool {
        names = []
        styleNames = []
        guard accessibilityPermission(promptIfNeeded: false) else {
            status = permissionMessage
            return false
        }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "jp.ai-j.AIVoice2").first else {
            status = "A.I.VOICE2が起動していません。"
            return false
        }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let deadline = Date().addingTimeInterval(2)
        var budget = 300
        var rows: [(String, AXUIElement)] = []
        let scopes: Set<String> = ["キャラクター一覧", "キャラクター一覧画面", "キャラクターリスト"]
        func walk(_ element: AXUIElement, inCatalog: Bool, depth: Int) {
            guard depth < 18, budget > 0, Date() < deadline else { return }
            budget -= 1
            let role = string(element, kAXRoleAttribute)
            let title = string(element, kAXTitleAttribute)
            let label = title.isEmpty ? string(element, kAXDescriptionAttribute) : title
            let inside = inCatalog || (scopes.contains(label) && role != kAXButtonRole)
            let children = elements(element, kAXChildrenAttribute)
            if inside && role == kAXRowRole {
                var labels = title.isEmpty ? [] : [title]
                if labels.isEmpty {
                    labels = children.filter { string($0, kAXRoleAttribute) == kAXStaticTextRole }
                        .map {
                            let value = string($0, kAXValueAttribute)
                            return value.isEmpty ? string($0, kAXTitleAttribute) : value
                        }.filter { !$0.isEmpty && $0 != "標準" }
                }
                let unique = Set(labels)
                if unique.count == 1, let name = unique.first, name.count <= 100 {
                    rows.append((name, element))
                }
                return
            }
            for child in children { walk(child, inCatalog: inside, depth: depth + 1) }
        }
        for window in elements(app, kAXWindowsAttribute) { walk(window, inCatalog: false, depth: 0) }
        names = Array(Set(rows.map(\.0))).sorted()
        guard !names.isEmpty else {
            status = "話者名を安全に読み取れる一覧が見つかりません。A.I.VOICE2のキャラクター一覧を開いて再読み取りしてください。画面がアクセシビリティ情報を公開しない場合、この方式では未対応です。"
            return false
        }
        styleNames = readStyleNames(app)
        status = "画面から\(names.count)件の話者"
            + (styleNames.isEmpty ? "" : "、\(styleNames.count)件のスタイル")
            + "を読み取りました（画面外を含む全ライブラリの取得は保証しません）。"
        guard let preferredName, !preferredName.isEmpty else { return true }
        let matches = rows.filter { $0.0 == preferredName }
        guard matches.count == 1 else {
            status += " プリセットの「\(preferredName)」は未確認または重複しているため選択しません。"
            return true
        }
        let row = matches[0].1
        if (attribute(row, kAXSelectedAttribute) as? Bool) == true {
            status += " プリセットの話者は一覧で選択済みです。"
            return true
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(row, kAXSelectedAttribute as CFString, &settable) == .success,
              settable.boolValue,
              AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success,
              (attribute(row, kAXSelectedAttribute) as? Bool) == true else {
            status += " 話者は見つかりましたが一覧の自動選択は未対応です。"
            return true
        }
        status += " プリセットに合わせて一覧の話者を選択しました。合成用話者・感情への適用は別途確認が必要です。"
        return true
    }

    private var permissionMessage: String {
        "話者読取には、このMacの「プライバシーとセキュリティ → アクセシビリティ」でボイスムービースタジオの許可が必要です。許可後に一覧を開いて再読み取りしてください。"
    }

    private func accessibilityPermission(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        guard promptIfNeeded, !didRequestAccessibilityPrompt else { return false }
        didRequestAccessibilityPrompt = true
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Reads only names exposed next to sliders inside a group labelled "スタイル".
    /// Core effect labels and numeric values are excluded; unknown labels are not invented.
    private func readStyleNames(_ app: AXUIElement) -> [String] {
        let excluded: Set<String> = [
            "スタイル", "音量", "話速", "高さ", "抑揚", "短ポーズ", "長ポーズ", "文末ポーズ",
            "保存", "初期値", "戻る"
        ]
        var result: Set<String> = []
        var budget = 500
        func strings(in element: AXUIElement, depth: Int) -> [String] {
            guard depth >= 0 else { return [] }
            var values = [string(element, kAXTitleAttribute), string(element, kAXValueAttribute)]
                .filter { !$0.isEmpty }
            if depth > 0 {
                for child in elements(element, kAXChildrenAttribute) { values += strings(in: child, depth: depth - 1) }
            }
            return values
        }
        func walk(_ element: AXUIElement, insideStyleGroup: Bool, depth: Int) {
            guard depth < 20, budget > 0 else { return }
            budget -= 1
            let local = strings(in: element, depth: 1)
            let inside = insideStyleGroup || local.contains { $0 == "スタイル" }
            if inside, string(element, kAXRoleAttribute) == kAXSliderRole,
               let rawParent = attribute(element, kAXParentAttribute) {
                let parent = rawParent as! AXUIElement
                for value in strings(in: parent, depth: 1) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    let numericDisplay = trimmed
                        .replacingOccurrences(of: "%", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                    guard !excluded.contains(trimmed), !trimmed.isEmpty, trimmed.count <= 40,
                          Double(numericDisplay) == nil else { continue }
                    result.insert(trimmed)
                }
            }
            for child in elements(element, kAXChildrenAttribute) {
                walk(child, insideStyleGroup: inside, depth: depth + 1)
            }
        }
        for window in elements(app, kAXWindowsAttribute) { walk(window, insideStyleGroup: false, depth: 0) }
        return result.sorted()
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func string(_ element: AXUIElement, _ name: String) -> String {
        (attribute(element, name) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }
}
