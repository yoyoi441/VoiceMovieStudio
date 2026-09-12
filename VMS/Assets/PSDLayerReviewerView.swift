import SwiftUI
import VMSCore

struct PSDLayerReviewerView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let characterID: UUID
    @State private var selectedLayerID: UUID?
    @State private var expressionName = "新しい表情"
    @State private var destinationFolderID: UUID?
    @State private var newFolderName = ""
    @State private var compareDefault = true

    private var character: Character? { store.project.characters.first { $0.id == characterID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PSDレイヤーレビュアー").font(.title3).bold()
                if let character { Text(character.name).foregroundColor(.secondary) }
                Spacer()
                Button("閉じる") { dismiss() }
            }
            .padding(12)
            Divider()

            HSplitView {
                layerList.frame(minWidth: 260, idealWidth: 320)
                preview.frame(minWidth: 420)
            }
            Divider()
            controls.padding(12)
        }
        .frame(minWidth: 980, idealWidth: 1240, minHeight: 680, idealHeight: 840)
    }

    private var layerList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("レイヤー").font(.headline).padding(.horizontal, 10).padding(.top, 10)
            Text("チェックを切り替えて表情を組み立てます。")
                .font(.caption).foregroundColor(.secondary).padding(.horizontal, 10)
            Text("一覧はPSDと同じ上→下の重なり順です。上の素材ほど手前に合成されます。")
                .font(.caption2).foregroundColor(.secondary).padding(.horizontal, 10)
            Button {
                store.restorePSDLayerSourceOrder(characterID: characterID)
            } label: {
                Label("PSDの元順に戻す", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("読み込んだPSD本来の上から下の順序へ戻す")
            .padding(.horizontal, 10)
            HStack {
                Button { moveSelectedToEdge(true) } label: { Label("一番上", systemImage: "arrow.up.to.line") }
                Button { moveSelected(-1) } label: { Label("上へ", systemImage: "arrow.up") }
                Button { moveSelected(1) } label: { Label("下へ", systemImage: "arrow.down") }
                Button { moveSelectedToEdge(false) } label: { Label("一番下", systemImage: "arrow.down.to.line") }
            }
            .buttonStyle(.borderless)
            .disabled(selectedLayerID == nil)
            .padding(.horizontal, 10)
            HStack(spacing: 6) {
                TextField("新規フォルダー名", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                Button("作成") {
                    store.createPSDLayerFolder(characterID: characterID, name: newFolderName, parentFolderID: destinationFolderID)
                    newFolderName = ""
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            HStack(spacing: 6) {
                Picker("移動先", selection: $destinationFolderID) {
                    Text("最上位").tag(UUID?.none)
                    ForEach(folderOptions, id: \.id) { option in
                        Text(option.title).tag(Optional(option.id))
                    }
                }
                .labelsHidden()
                Button("選択素材を移動") {
                    guard let selectedLayerID else { return }
                    store.movePSDLayer(characterID: characterID, layerID: selectedLayerID, toFolderID: destinationFolderID)
                }
                .disabled(selectedLayerID == nil)
            }
            .padding(.horizontal, 10)
            List(selection: $selectedLayerID) {
                PSDLayerTreeRows(characterID: characterID, nodes: character?.layerTree ?? [], selection: $selectedLayerID)
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            Toggle("保存済みデフォルトと並べて比較", isOn: $compareDefault).padding(8)
            HSplitView {
                VStack {
                    Text("編集中のレイヤー").font(.caption).bold()
                    compositionPreview
                }.frame(minWidth: 210)
                if compareDefault {
                    VStack {
                        Text("保存済みデフォルト").font(.caption).bold()
                        ZStack {
                            checkerboard
                            if let character {
                                let file = character.expressions.first(where: { $0.id == character.defaultExpressionID })?.imageFileName ?? character.baseImageFileName
                                if let image = store.imageProvider.image(named: file) {
                                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(16)
                                } else {
                                    Text("デフォルト画像がありません").font(.caption)
                                }
                            }
                        }
                    }.frame(minWidth: 210)
                }
            }
            Divider()
            selectedPartPreview.frame(minHeight: 180, idealHeight: 220, maxHeight: 260)
        }
    }

    private var compositionPreview: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                checkerboard
                ZStack {
                    ForEach(Array(visibleLayers.reversed())) { layer in
                        if let file = layer.imageFileName, let image = store.imageProvider.image(named: file) {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        }
                    }
                }
                .padding(16)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var selectedPartPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("選択パーツの拡大プレビュー").font(.caption).bold()
                Spacer()
                Text(selectedLayerID.flatMap(currentLayer)?.name ?? "レイヤーを選択してください")
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.top, 8)
            ZStack {
                checkerboard
                if let layer = selectedLayerID.flatMap(currentLayer), let file = layer.imageFileName,
                   let image = store.imageProvider.croppedToVisibleContent(named: file) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(12)
                } else {
                    Text("口・目などのレイヤーを選択すると、透明部分を除いて大きく表示します。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let unit: CGFloat = 14
            for y in stride(from: CGFloat(0), to: size.height, by: unit) {
                for x in stride(from: CGFloat(0), to: size.width, by: unit) {
                    let odd = (Int(x / unit) + Int(y / unit)) % 2 == 0
                    context.fill(Path(CGRect(x: x, y: y, width: unit, height: unit)), with: .color(odd ? .white : Color.gray.opacity(0.18)))
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let character {
                HStack(spacing: 8) {
                    Text("設定状況：").font(.caption).foregroundColor(.secondary)
                    status("デフォルト", isSet: character.defaultExpressionID != nil)
                    status("口・通常", isSet: character.mouthImageFileNames[.closed] != nil)
                    status("口・小", isSet: character.mouthImageFileNames[.small] != nil)
                    status("口・開", isSet: character.mouthImageFileNames[.open] != nil)
                    status("目・開", isSet: character.eyeImageFileNames[.open] != nil)
                    status("目・閉", isSet: character.eyeImageFileNames[.closed] != nil)
                    Text("表情 \(character.expressions.count)件").font(.caption)
                }
            }
            HStack {
                Text("選択レイヤーを割り当て：").font(.caption).foregroundColor(.secondary)
                Button("口・閉") { assignMouth(.closed) }.disabled(selectedLayerID == nil)
                Button("口・小") { assignMouth(.small) }.disabled(selectedLayerID == nil)
                Button("口・開") { assignMouth(.open) }.disabled(selectedLayerID == nil)
                Divider().frame(height: 20)
                Button("目・開") { assignEye(.open) }.disabled(selectedLayerID == nil)
                Button("目・閉") { assignEye(.closed) }.disabled(selectedLayerID == nil)
            }
            HStack {
                Button("現在の組み合わせを通常画像にする") { store.savePSDComposite(characterID: characterID, expressionName: nil) }
                Spacer()
                TextField("表情名", text: $expressionName).frame(width: 180)
                Button("表情として保存") { store.savePSDComposite(characterID: characterID, expressionName: expressionName) }
                    .disabled(expressionName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("デフォルトとして保存") {
                    store.savePSDComposite(characterID: characterID, expressionName: expressionName, setAsDefault: true)
                }
                .disabled(expressionName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .buttonStyle(.bordered)
    }

    private var visibleLayers: [TachieLayerNode] { flattenVisible(character?.layerTree ?? []) }
    private var folderOptions: [(id: UUID, title: String)] {
        func collect(_ nodes: [TachieLayerNode], prefix: String) -> [(UUID, String)] {
            nodes.flatMap { node -> [(UUID, String)] in
                guard node.isFolder else { return [] }
                let title = prefix + node.name
                return [(node.id, title)] + collect(node.children, prefix: title + " / ")
            }
        }
        return collect(character?.layerTree ?? [], prefix: "")
    }
    private func flattenVisible(_ nodes: [TachieLayerNode], parentVisible: Bool = true) -> [TachieLayerNode] {
        nodes.flatMap { node -> [TachieLayerNode] in
            let visible = parentVisible && node.isVisible
            return node.isFolder ? flattenVisible(node.children, parentVisible: visible) : (visible ? [node] : [])
        }
    }
    private func currentLayer(_ id: UUID) -> TachieLayerNode? {
        func find(_ nodes: [TachieLayerNode]) -> TachieLayerNode? {
            for node in nodes {
                if node.id == id { return node }
                if let found = find(node.children) { return found }
            }
            return nil
        }
        return find(character?.layerTree ?? [])
    }
    private func assignMouth(_ shape: MouthShape) {
        guard let selectedLayerID else { return }
        store.assignPSDLayer(characterID: characterID, layerID: selectedLayerID, mouthShape: shape)
    }
    private func assignEye(_ shape: EyeShape) {
        guard let selectedLayerID else { return }
        store.assignPSDLayer(characterID: characterID, layerID: selectedLayerID, eyeShape: shape)
    }
    private func moveSelected(_ direction: Int) {
        guard let selectedLayerID else { return }
        store.movePSDLayer(characterID: characterID, layerID: selectedLayerID, direction: direction)
    }
    private func moveSelectedToEdge(_ toTop: Bool) {
        guard let selectedLayerID else { return }
        store.movePSDLayerToEdge(characterID: characterID, layerID: selectedLayerID, toTop: toTop)
    }
    private func status(_ title: String, isSet: Bool) -> some View {
        Label(title, systemImage: isSet ? "checkmark.circle.fill" : "circle")
            .font(.caption2)
            .foregroundColor(isSet ? .green : .secondary)
    }
}

private struct PSDLayerTreeRows: View {
    @Environment(ProjectStore.self) private var store
    let characterID: UUID
    let nodes: [TachieLayerNode]
    @Binding var selection: UUID?

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                DisclosureGroup {
                    PSDLayerTreeRows(characterID: characterID, nodes: node.children, selection: $selection)
                        .padding(.leading, 12)
                } label: { row(node, folder: true) }
            } else {
                row(node, folder: false)
            }
        }
    }

    private func row(_ node: TachieLayerNode, folder: Bool) -> some View {
        HStack(spacing: 7) {
            Toggle("", isOn: Binding(
                get: { find(node.id)?.isVisible ?? false },
                set: { store.setPSDLayerVisibility(characterID: characterID, layerID: node.id, isVisible: $0) }
            )).labelsHidden()
            if folder {
                Image(systemName: "folder").foregroundColor(.secondary).frame(width: 28)
            } else if let file = node.imageFileName, let image = store.imageProvider.croppedToVisibleContent(named: file) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
            } else { Image(systemName: "square.stack").frame(width: 28) }
            Text(node.name).lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .background(selection == node.id ? Color.accentColor.opacity(0.15) : .clear)
        .onTapGesture { selection = node.id }
    }

    private func find(_ id: UUID) -> TachieLayerNode? {
        func search(_ items: [TachieLayerNode]) -> TachieLayerNode? {
            for item in items {
                if item.id == id { return item }
                if let found = search(item.children) { return found }
            }
            return nil
        }
        guard let character = store.project.characters.first(where: { $0.id == characterID }) else { return nil }
        return search(character.layerTree)
    }
}
