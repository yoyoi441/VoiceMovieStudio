import SwiftUI
import VMSCore

/// §2: one tab per `Scene` in the current project. Add/close/rename/switch/reorder are
/// all real, backed by `ProjectStore`'s scene methods (see `ProjectStore.swift`) — there's
/// no separate "scene UI state," the tab bar just reflects `project.scenes`.
struct SceneTabBar: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            // Drag-to-reorder is spec'd as optional ("可能なら"); `ForEach.onMove` only
            // provides reordering UI inside a `List`, which a compact horizontal tab bar
            // isn't, so this stays click-to-switch only for now. `ProjectStore.moveScene`
            // is ready for a custom drag implementation later.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(store.project.scenes) { scene in
                        SceneTabButton(scene: scene)
                    }
                }
            }

            Button {
                store.addScene()
            } label: {
                IconCatalog.resolve(.sceneAdd).font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("新規シーン追加")

            Menu {
                ForEach(store.project.scenes) { scene in
                    Button(scene.name) { store.selectScene(id: scene.id) }
                }
            } label: {
                IconCatalog.resolve(.sceneMenu).font(.system(size: 9))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 16)
            .help("シーン一覧")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: Theme.sceneTabHeight)
        .background(Theme.panelBackground)
        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .bottom)
    }
}

private struct SceneTabButton: View {
    @Environment(ProjectStore.self) private var store
    let scene: VMSCore.Scene

    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let isSelected = store.currentSceneID == scene.id

        HStack(spacing: 4) {
            if isEditingName {
                TextField("シーン名", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(Theme.labelFont)
                    .focused($isFieldFocused)
                    .onSubmit { commitRename() }
                    .onChange(of: isFieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
                    .frame(width: 90)
            } else {
                Text(scene.name)
                    .font(Theme.labelFont)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename() })
            }

            if store.project.scenes.count > 1 {
                Button {
                    store.removeScene(id: scene.id)
                } label: {
                    IconCatalog.resolve(.sceneClose).font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .help("シーンを閉じる")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.sceneTabHeight - 6)
        .background(isSelected ? Theme.selectionFill : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isSelected ? Theme.selectionBorder : Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { store.selectScene(id: scene.id) }
        .contextMenu {
            Button("名前を変更") { beginRename() }
            if store.project.scenes.count > 1 {
                Button("閉じる", role: .destructive) { store.removeScene(id: scene.id) }
            }
        }
        .accessibilityLabel(Text("シーン: \(scene.name)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func beginRename() {
        editedName = scene.name
        isEditingName = true
        isFieldFocused = true
    }

    private func commitRename() {
        guard isEditingName else { return }
        isEditingName = false
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            store.renameScene(id: scene.id, to: trimmed)
        }
    }
}
