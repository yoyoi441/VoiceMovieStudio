import SwiftUI
import VMSCore

/// §7-6: expand/collapse, folder display, per-layer visibility, selection, scroll — over
/// `Character.layerTree`. There's no PSD parser behind this, so the tree is inert
/// placeholder data (see `Character.defaultLayerTree`); toggling a layer's visibility
/// here doesn't change the render yet, only the data model, exactly as the spec allows
/// for this stage ("PSD解析自体が未実装の場合でも...保持できるようにします").
struct LayerTree: View {
    @Environment(ProjectStore.self) private var store
    let character: Character

    @State private var selectedNodeID: UUID?
    @State private var expandedIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(character.layerTree) { node in
                    LayerNodeRow(
                        node: node,
                        depth: 0,
                        characterID: character.id,
                        selectedNodeID: $selectedNodeID,
                        expandedIDs: $expandedIDs
                    )
                }
                if character.layerTree.isEmpty {
                    Text("レイヤーがありません").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxHeight: 150)
        .background(Theme.canvasBackground)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }
}

private struct LayerNodeRow: View {
    @Environment(ProjectStore.self) private var store
    let node: TachieLayerNode
    let depth: Int
    let characterID: UUID
    @Binding var selectedNodeID: UUID?
    @Binding var expandedIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Spacer().frame(width: CGFloat(depth) * 12)

                if node.isFolder {
                    Button {
                        toggleExpanded()
                    } label: {
                        IconCatalog.resolve(expandedIDs.contains(node.id) ? .chevronExpanded : .chevronCollapsed)
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                Button {
                    toggleVisible()
                } label: {
                    IconCatalog.resolve(node.isVisible ? .visible : .hidden)
                        .font(.system(size: 9))
                        .foregroundColor(node.isVisible ? .primary : .secondary)
                }
                .buttonStyle(.plain)

                if node.isFolder {
                    IconCatalog.resolve(.folder).font(.system(size: 9)).foregroundColor(.secondary)
                }

                Text(node.name).font(.caption2).lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(selectedNodeID == node.id ? Theme.selectionFill : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { selectedNodeID = node.id }

            if node.isFolder && expandedIDs.contains(node.id) {
                ForEach(node.children) { child in
                    LayerNodeRow(node: child, depth: depth + 1, characterID: characterID, selectedNodeID: $selectedNodeID, expandedIDs: $expandedIDs)
                }
            }
        }
    }

    private func toggleExpanded() {
        if expandedIDs.contains(node.id) {
            expandedIDs.remove(node.id)
        } else {
            expandedIDs.insert(node.id)
        }
    }

    private func toggleVisible() {
        guard let charIndex = store.project.characters.firstIndex(where: { $0.id == characterID }) else { return }
        store.beginUndoableChange()
        Self.toggle(node.id, in: &store.project.characters[charIndex].layerTree)
    }

    private static func toggle(_ id: UUID, in nodes: inout [TachieLayerNode]) {
        for index in nodes.indices {
            if nodes[index].id == id {
                nodes[index].isVisible.toggle()
                return
            }
            toggle(id, in: &nodes[index].children)
        }
    }
}
