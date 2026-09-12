import AppKit
import SwiftUI
import VMSCore

/// §7-6. Most of the fields the spec lists for 立ち絵 (X/Y/Z, opacity, scale, rotation,
/// fade, blend mode, flip, front/z-order, clipping, effect list) are the same "共通"
/// properties every clip has, shown by `CommonPropertiesSection` right after this one —
/// this section only covers what's actually specific to a tachie item.
struct TachieInspector: View {
    @Environment(ProjectStore.self) private var store
    let primary: Clip

    var body: some View {
        guard case .character(let data) = primary.content,
              let character = store.project.character(withID: data.characterID) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            PropertySection("立ち絵") {
                Text(character.name).font(.subheadline).bold()

                SelectPropertyControl(
                    label: "種類",
                    value: Binding<TachieKind?>(
                        get: { character.tachieKind },
                        set: { newValue in
                            guard let newValue else { return }
                            setCharacter(data.characterID) { $0.tachieKind = newValue }
                        }
                    ),
                    options: TachieKind.selectableCases.map { ($0, $0.displayName) }
                )
                if !character.tachieKind.isImplemented {
                    Text("この種類の映像処理は未対応です(選択と保存のみ可能)。").font(.caption2).foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Text("ファイル").font(Theme.labelFont).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                    Text(character.baseImageFileName).font(.caption2).lineLimit(1).foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Button("ファイル選択…") { pickBaseImage(for: data.characterID) }
                    Button("再読み込み") { store.imageProvider.invalidate(fileName: character.baseImageFileName) }
                }
                .font(.caption)

                TogglePropertyControl(
                    label: "喋る時のみ表示",
                    value: store.mixedBinding(
                        get: { clip in guard case .character(let d) = clip.content else { return false }; return d.visibleOnlyWhenSpeaking },
                        set: { clip, newValue in guard case .character(var d) = clip.content else { return }; d.visibleOnlyWhenSpeaking = newValue; clip.content = .character(d) }
                    )
                )

                HStack(spacing: 6) {
                    Text("表情").font(Theme.labelFont).foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: Binding<UUID?>(
                        get: { data.expressionID },
                        set: { setExpression($0) }
                    )) {
                        Text("デフォルト").tag(UUID?.none)
                        ForEach(character.expressions) { expression in
                            Text(expression.name).tag(Optional(expression.id))
                        }
                    }
                    .labelsHidden()
                }
                Text("プリセット(未実装)").font(.caption2).foregroundColor(.secondary)

                Divider()
                Text("レイヤーツリー").font(Theme.labelFont).bold()
                LayerTree(character: character)
            }
        )
    }

    private func pickBaseImage(for characterID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fileName = try AssetImporter.importFile(from: url, into: store.assetsDirectory, prefix: "char")
            setCharacter(characterID) { $0.baseImageFileName = fileName }
            store.imageProvider.invalidate(fileName: fileName)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func setCharacter(_ id: UUID, _ mutate: (inout Character) -> Void) {
        guard let index = store.project.characters.firstIndex(where: { $0.id == id }) else { return }
        store.beginUndoableChange()
        mutate(&store.project.characters[index])
    }

    private func setExpression(_ expressionID: UUID?) {
        store.beginUndoableChange()
        for clip in store.selectedClips {
            guard case .character(var data) = clip.content else { continue }
            var updated = clip
            data.expressionID = expressionID
            updated.content = .character(data)
            store.updateClip(updated)
        }
    }
}
