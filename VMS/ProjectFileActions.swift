import AppKit
import VMSCore

/// NSSavePanel/NSOpenPanel glue for `.VMS` project packages. Kept separate from
/// `ProjectStore` so the store itself stays free of AppKit dependencies.
@MainActor
enum ProjectFileActions {
    static func promptSaveAs(store: ProjectStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(store.documentDisplayName).\(ProjectPackage.fileExtension)"
        panel.canCreateDirectories = true
        panel.title = "プロジェクトを保存"
        guard panel.runModal() == .OK, var url = panel.url else { return }
        if url.pathExtension != ProjectPackage.fileExtension {
            url = url.appendingPathExtension(ProjectPackage.fileExtension)
        }
        store.save(to: url)
    }

    static func save(store: ProjectStore) {
        if !store.saveInPlace() {
            promptSaveAs(store: store)
        }
    }

    static func promptOpen(store: ProjectStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "プロジェクトを開く"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.open(from: url)
    }
}
