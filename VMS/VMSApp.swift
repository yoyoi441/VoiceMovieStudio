import SwiftUI

@main
struct VMSApp: App {
    @State private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 700)
                .task {
                    CommandRegistry.assertAllCommandsRegistered()
                    RemoteAIController.importBootstrapTokenIfNeeded()
                    UpdateController.shared.projectStore = store
                    if let recovery = UserDefaults.standard.string(forKey: "updates.pendingRecovery") {
                        store.open(from: URL(fileURLWithPath: recovery))
                        if store.currentPackageURL != nil {
                            UserDefaults.standard.removeObject(forKey: "updates.pendingRecovery")
                        }
                    }
                    await store.importLaunchMaterialsIfNeeded()
                }
        }
        .commands {
            // Only shortcuts that can't collide with ordinary text editing (renaming a
            // scene/track, typing clip text, the project-settings fields, …) live here as
            // global menu commands. Selection-editing shortcuts that *do* overlap with
            // text editing (⌘X/⌘C/⌘V/⌘A/Delete) are scoped to the timeline's own keyboard
            // focus instead (`TimelineView`'s `.onKeyPress`), the same way Final Cut/
            // Premiere keep those keys from hijacking a text field elsewhere in the window.
            CommandGroup(replacing: .undoRedo) {
                menuButton(.undo)
                menuButton(.redo)
            }
            CommandGroup(after: .newItem) {
                menuButton(.newProject)
                menuButton(.openProject)
                Divider()
                menuButton(.saveProject)
                menuButton(.saveProjectAs)
                Divider()
                menuButton(.splitAtPlayhead)
                menuButton(.bulkEdit)
                menuButton(.togglePlayback)
                Divider()
                menuButton(.exportVideo)
                menuButton(.manageCharacters)
            }
            CommandGroup(replacing: .help) {
                UpdateMenu()
                Divider()
                Button("ヘルプセンター") { store.isShowingHelp = true }
                    .keyboardShortcut("?", modifiers: [.command])
                Button("チュートリアルを表示") { store.isShowingTutorial = true }
            }
            CommandMenu("AI") {
                Button("AI編集支援を開く") { store.isShowingRemoteAI = true }
            }
        }
    }

    @ViewBuilder
    private func menuButton(_ id: CommandID) -> some View {
        let command = CommandRegistry.command(id)
        let context = EditorContext(store: store)
        Button(command.title) {
            command.perform(context)
        }
        .disabled(!command.isEnabled(context))
        .modifierIfShortcut(command.shortcut)
    }
}

private extension View {
    @ViewBuilder
    func modifierIfShortcut(_ shortcut: KeyboardShortcutSpec?) -> some View {
        if let shortcut {
            self.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            self
        }
    }
}
