import SwiftUI
import VMSCore

/// Selects one extracted image layer from the character's imported PSD and assigns it
/// to an ordered mouth/eye animation frame. It deliberately never opens the PSD in an
/// external application: the whole operation stays inside the character manager.
struct PSDCharacterPartPickerView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let characterID: UUID
    let part: CharacterPartKind
    let frameID: UUID

    @State private var selection: UUID?
    @State private var searchText = ""

    private var character: Character? {
        store.project.characters.first { $0.id == characterID }
    }

    private var frame: CharacterPartFrame? {
        let frames = part == .mouth ? character?.mouthAnimationFrames : character?.eyeAnimationFrames
        return frames?.first { $0.id == frameID }
    }

    private var allLayers: [SelectablePSDLayer] {
        func visibleFiles(_ nodes: [TachieLayerNode], parentVisible: Bool = true) -> [String] {
            nodes.flatMap { node -> [String] in
                let visible = parentVisible && node.isVisible
                if node.isFolder { return visibleFiles(node.children, parentVisible: visible) }
                guard visible, let file = node.imageFileName else { return [] }
                return [file]
            }
        }
        func flatten(_ nodes: [TachieLayerNode], path: String) -> [SelectablePSDLayer] {
            nodes.flatMap { node -> [SelectablePSDLayer] in
                let nextPath = path.isEmpty ? node.name : "\(path) / \(node.name)"
                if node.isFolder {
                    let folder = SelectablePSDLayer(
                        id: node.id, name: node.name, path: nextPath,
                        imageFileNames: visibleFiles(node.children), isFolder: true
                    )
                    return [folder] + flatten(node.children, path: nextPath)
                }
                guard let imageFileName = node.imageFileName else { return [] }
                return [SelectablePSDLayer(id: node.id, name: node.name, path: nextPath, imageFileNames: [imageFileName], isFolder: false)]
            }
        }
        return flatten(character?.layerTree ?? [], path: "")
    }

    private var layers: [SelectablePSDLayer] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? allLayers : allLayers.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    private var selectedLayer: SelectablePSDLayer? {
        guard let selection else { return nil }
        return layers.first { $0.id == selection }
            ?? allLayers.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PSDレイヤーから割り当て").font(.title3).bold()
                    Text("\(part == .mouth ? "口パク" : "目パチ")・\(frame?.name ?? "フレーム")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("キャンセル") { dismiss() }
            }
            .padding(12)
            Divider()

            HSplitView {
                VStack(spacing: 8) {
                    TextField("レイヤー名を検索", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 10).padding(.top, 10)
                    Group {
                        if allLayers.isEmpty {
                            ContentUnavailableView(
                                "PSDレイヤーがありません",
                                systemImage: "square.3.layers.3d.slash",
                                description: Text("キャラクター管理でPSDの表示を再読み込みしてください。")
                            )
                        } else {
                            List(selection: $selection) {
                                ForEach(layers) { layer in
                                    HStack(spacing: 8) {
                                        if !layer.isFolder, let file = layer.imageFileNames.first,
                                           let image = store.imageProvider.croppedToVisibleContent(named: file) {
                                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                                                .frame(width: 34, height: 34)
                                        } else {
                                            Image(systemName: layer.isFolder ? "folder" : "square.3.layers.3d").frame(width: 34, height: 34)
                                        }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(layer.name).lineLimit(1)
                                            Text(layer.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    .tag(layer.id)
                                }
                            }
                        }
                    }
                    Text("PSD内の画像レイヤーとフォルダーを表示しています。フォルダーは表示中の子レイヤーをまとめて割り当てます。")
                        .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 8)
                }
                .frame(minWidth: 330, idealWidth: 390)

                VStack(alignment: .leading, spacing: 8) {
                    Text("選択レイヤーのプレビュー").font(.headline)
                    ZStack {
                        checkerboard
                        if let image = selectedPreviewImage {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(24)
                        } else {
                            ContentUnavailableView(
                                "レイヤーを選択",
                                systemImage: "square.3.layers.3d",
                                description: Text("左の一覧から口または目のパーツを選んでください。")
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    if let selectedLayer {
                        Text(selectedLayer.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(minWidth: 390)
            }

            Divider()
            HStack {
                Text("割り当て後も元のPSDとレイヤー構造は保持されます。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("このレイヤーを割り当て") {
                    guard let selection else { return }
                    store.assignPSDLayer(characterID: characterID, layerID: selection, part: part, frameID: frameID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedLayer?.imageFileNames.isEmpty != false)
            }
            .padding(12)
        }
        .frame(minWidth: 840, idealWidth: 980, minHeight: 620, idealHeight: 720)
        .onAppear { selection = frame?.sourceLayerID }
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let unit: CGFloat = 16
            for y in stride(from: CGFloat(0), to: size.height, by: unit) {
                for x in stride(from: CGFloat(0), to: size.width, by: unit) {
                    let odd = (Int(x / unit) + Int(y / unit)) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: unit, height: unit)),
                        with: .color(odd ? .white : Color.gray.opacity(0.2))
                    )
                }
            }
        }
    }

    private var selectedPreviewImage: NSImage? {
        guard let selectedLayer, let firstName = selectedLayer.imageFileNames.first else { return nil }
        if selectedLayer.imageFileNames.count == 1 {
            return store.imageProvider.croppedToVisibleContent(named: firstName)
        }
        guard let first = store.imageProvider.image(named: firstName) else { return nil }
        let image = NSImage(size: first.size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        for file in selectedLayer.imageFileNames.reversed() {
            store.imageProvider.image(named: file)?.draw(
                in: NSRect(origin: .zero, size: first.size), from: .zero,
                operation: .sourceOver, fraction: 1
            )
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.bitmapData else { return image }
        guard bitmap.samplesPerPixel >= 4 else { return image }
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = data + y * bitmap.bytesPerRow
            for x in 0..<width where row[x * bitmap.samplesPerPixel + 3] > 3 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let cg = bitmap.cgImage?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return image }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

private struct SelectablePSDLayer: Identifiable {
    let id: UUID
    let name: String
    let path: String
    let imageFileNames: [String]
    let isFolder: Bool
}
