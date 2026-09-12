import AppKit
import Observation

/// Loads character art from the project's Assets directory and caches the decoded
/// `NSImage`s in memory — the preview canvas redraws at up to 30fps during playback and
/// export re-renders every output frame, so re-reading from disk each time would be slow.
@Observable
@MainActor
final class CharacterImageProvider {
    private(set) var assetsDirectory: URL
    private var cache: [String: NSImage] = [:]
    private var croppedCache: [String: NSImage] = [:]

    init(assetsDirectory: URL) {
        self.assetsDirectory = assetsDirectory
    }

    /// Call when the project's asset folder changes (e.g. after opening a different project).
    func updateAssetsDirectory(_ url: URL) {
        guard url != assetsDirectory else { return }
        assetsDirectory = url
        cache.removeAll()
        croppedCache.removeAll()
    }

    /// Drop cached images for a specific file (e.g. after re-importing/replacing it).
    func invalidate(fileName: String) {
        cache.removeValue(forKey: fileName)
        croppedCache.removeValue(forKey: fileName)
    }

    func image(named fileName: String) -> NSImage? {
        if let cached = cache[fileName] {
            return cached
        }
        let url = assetsDirectory.appendingPathComponent(fileName)
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[fileName] = image
        return image
    }

    func croppedToVisibleContent(named fileName: String) -> NSImage? {
        if let cached = croppedCache[fileName] { return cached }
        guard let source = image(named: fileName) else { return nil }
        guard let tiff = source.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.bitmapData else { return source }
        let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        guard width > 0, height > 0, bitmap.samplesPerPixel >= 4 else { return source }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = data + y * bitmap.bytesPerRow
            for x in 0..<width where row[x * bitmap.samplesPerPixel + 3] > 3 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY, let cg = bitmap.cgImage?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return source }
        let cropped = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        croppedCache[fileName] = cropped
        return cropped
    }
}
