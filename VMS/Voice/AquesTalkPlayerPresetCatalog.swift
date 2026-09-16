import AppKit
import ApplicationServices
import Observation
import VMSCore

/// Reads only the preset-name popup exposed by AquesTalk Player's accessibility tree.
/// It never parses or modifies the product's private files and never guesses names.
@Observable
@MainActor
final class AquesTalkPlayerPresetCatalog {
    private(set) var names: [String] = []
    private(set) var status = "プリセット一覧はまだ読み取っていません。"
    private(set) var isBusy = false
    private var didRequestAccessibilityPrompt = false

    func launchAndRead() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard accessibilityPermission(promptIfNeeded: true) else {
            status = permissionMessage
            return
        }
        do {
            try await AquesTalkPlayerService.launch()
            for attempt in 0..<5 {
                if await readFromRunningApplication() { return }
                if !AXIsProcessTrusted() { return }
                if attempt < 4 { try await Task.sleep(for: .milliseconds(500)) }
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func refresh(promptIfNeeded: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard accessibilityPermission(promptIfNeeded: promptIfNeeded) else {
            status = permissionMessage
            return
        }
        _ = await readFromRunningApplication()
    }

    @discardableResult
    private func readFromRunningApplication() async -> Bool {
        guard let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: AquesTalkPlayerSupport.bundleIdentifier)
            .first(where: { !$0.isTerminated }) else {
            names = []
            status = "AquesTalk Playerが起動していません。「起動して一覧を読む」を押してください。"
            return false
        }

        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let popup = presetPopup(in: app) else {
            names = []
            status = "プリセット選択欄を読み取れませんでした。Playerの基本画面を開いて再読み取りしてください。"
            return false
        }
        let current = string(popup, kAXValueAttribute)
        guard AXUIElementPerformAction(popup, kAXPressAction as CFString) == .success else {
            names = current.isEmpty ? [] : [current]
            status = "プリセットメニューを開けませんでした。アクセシビリティ許可を確認してください。"
            return false
        }
        try? await Task.sleep(for: .milliseconds(180))

        let menuItems = presetMenuItems(popup: popup, app: app)
        let readNames = AquesTalkPlayerSupport.normalizedPresetNames(
            menuItems.map { string($0, kAXTitleAttribute) }
        )
        closeMenu(popup: popup, menuItems: menuItems, currentName: current)

        guard !readNames.isEmpty else {
            names = current.isEmpty ? [] : [current]
            status = "プリセット一覧を確認できませんでした。Playerの基本画面を前面に出して再読み取りしてください。"
            return false
        }
        names = readNames
        status = "AquesTalk Playerから\(readNames.count)件のプリセットを読み取りました。"
        return true
    }

    private func presetPopup(in app: AXUIElement) -> AXUIElement? {
        var matches: [AXUIElement] = []
        var allPopups: [AXUIElement] = []
        var budget = 350
        let deadline = Date().addingTimeInterval(2)
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 18, budget > 0, Date() < deadline else { return }
            budget -= 1
            if string(element, kAXRoleAttribute) == kAXPopUpButtonRole {
                allPopups.append(element)
                let labels = [
                    string(element, kAXTitleAttribute),
                    string(element, kAXDescriptionAttribute),
                    string(element, kAXHelpAttribute)
                ]
                if labels.contains(where: isPresetLabel) || nearbyStaticLabels(of: element).contains(where: isPresetLabel) {
                    matches.append(element)
                    return
                }
            }
            for child in elements(element, kAXChildrenAttribute) { walk(child, depth: depth + 1) }
        }
        for window in elements(app, kAXWindowsAttribute) { walk(window, depth: 0) }
        if matches.count == 1 { return matches[0] }

        // The current Mac build exposes the visible label only as a neighbouring
        // element. Its documented preferences domain still records the last selected
        // preset, which lets us identify exactly one popup without opening private files.
        if let lastPreset = UserDefaults.standard
            .persistentDomain(forName: AquesTalkPlayerSupport.bundleIdentifier)?["lastPresetName"] as? String {
            let valueMatches = allPopups.filter { string($0, kAXValueAttribute) == lastPreset }
            if valueMatches.count == 1 { return valueMatches[0] }
        }
        return nil
    }

    private func isPresetLabel(_ value: String) -> Bool {
        value == "プリセット名" || value == "プリセット"
    }

    /// AppKit can expose a popup without AXTitle/AXDescription and let System Events
    /// synthesize its name from a neighbouring static label. Mirror that behaviour by
    /// inspecting only static text close to the popup, never arbitrary document text.
    private func nearbyStaticLabels(of popup: AXUIElement) -> [String] {
        var result: [String] = []
        var current: AXUIElement? = popup
        for _ in 0..<3 {
            guard let element = current, let rawParent = attribute(element, kAXParentAttribute) else { break }
            let parent = rawParent as! AXUIElement
            var budget = 40
            func collect(_ candidate: AXUIElement, depth: Int) {
                guard depth <= 2, budget > 0 else { return }
                budget -= 1
                if string(candidate, kAXRoleAttribute) == kAXStaticTextRole {
                    let value = string(candidate, kAXValueAttribute)
                    result.append(value.isEmpty ? string(candidate, kAXTitleAttribute) : value)
                    return
                }
                for child in elements(candidate, kAXChildrenAttribute) { collect(child, depth: depth + 1) }
            }
            collect(parent, depth: 0)
            current = parent
        }
        return result
    }

    private func presetMenuItems(popup: AXUIElement, app: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var budget = 500
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 18, budget > 0 else { return }
            budget -= 1
            if string(element, kAXRoleAttribute) == kAXMenuItemRole {
                result.append(element)
                return
            }
            for child in elements(element, kAXChildrenAttribute) { walk(child, depth: depth + 1) }
        }
        walk(popup, depth: 0)
        if result.isEmpty {
            for window in elements(app, kAXWindowsAttribute) { walk(window, depth: 0) }
        }
        return result
    }

    private func closeMenu(popup: AXUIElement, menuItems: [AXUIElement], currentName: String) {
        if let current = menuItems.first(where: { string($0, kAXTitleAttribute) == currentName }),
           AXUIElementPerformAction(current, kAXPressAction as CFString) == .success {
            return
        }
        _ = AXUIElementPerformAction(popup, kAXPressAction as CFString)
    }

    private var permissionMessage: String {
        "プリセット読取には、このMacの「プライバシーとセキュリティ → アクセシビリティ」でボイスムービースタジオの許可が必要です。許可後に再読み取りしてください。"
    }

    private func accessibilityPermission(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        guard promptIfNeeded, !didRequestAccessibilityPrompt else { return false }
        didRequestAccessibilityPrompt = true
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
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
