import AVFoundation
import AppKit
import VMSCore

/// The real (non-stub) "add item" toolbar commands — everything the current data model
/// can already represent. See `CommandRegistry.addItemCommands` for the full button list,
/// including the ones registered but disabled until their clip type/feature exists.
extension ProjectStore {
    func promptAddVideoItem() {
        VideoAssetImporter.promptAndImport(into: self, addToTimeline: true)
    }
    func addTextItem() {
        addClip(content: .text(TextClipData(text: "新しいテキスト")), duration: 3)
    }

    func addCharacterItem() {
        guard let character = project.characters.first else {
            errorMessage = "先にキャラクターを追加してください(「キャラクター管理」から追加できます)。"
            return
        }
        addClip(
            content: .character(CharacterClipData(characterID: character.id)),
            duration: 3,
            effects: ClipEffects(flipHorizontal: character.defaultFlipHorizontal)
        )
    }

    func promptAddImageItem() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fileName = try AssetImporter.importFile(from: url, into: assetsDirectory, prefix: "image")
            addClip(content: .image(ImageClipData(fileName: fileName)), duration: 3)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports the file synchronously, then reads its actual duration and inserts the
    /// clip asynchronously (loading an `AVURLAsset`'s duration is an async API) — the
    /// insertion point is captured up front so a later playhead move can't shift it.
    func promptAddAudioItem() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let fileName = try AssetImporter.importFile(from: url, into: assetsDirectory, prefix: "audio")
            let fileURL = assetsDirectory.appendingPathComponent(fileName)
            let insertionTime = playhead
            Task {
                let duration = (try? await AVURLAsset(url: fileURL).load(.duration).seconds) ?? 3
                addClip(content: .audio(AudioClipData(fileName: fileName)), duration: max(0.1, duration), at: insertionTime)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
