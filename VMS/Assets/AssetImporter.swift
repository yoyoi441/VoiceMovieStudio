import Foundation

enum AssetImporter {
    enum ImportError: Error, LocalizedError {
        case copyFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .copyFailed(let underlying):
                return "ファイルのコピーに失敗しました: \(underlying.localizedDescription)"
            }
        }
    }

    /// Copies `sourceURL` into `assetsDirectory` under a fresh generated name (keeping the
    /// original extension) and returns that file name. Generating a fresh name avoids
    /// collisions when multiple characters import files with the same original name.
    static func importFile(from sourceURL: URL, into assetsDirectory: URL, prefix: String) throws -> String {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
            let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
            let fileName = "\(prefix)_\(UUID().uuidString).\(ext)"
            let destination = assetsDirectory.appendingPathComponent(fileName)
            try fileManager.copyItem(at: sourceURL, to: destination)
            return fileName
        } catch {
            throw ImportError.copyFailed(underlying: error)
        }
    }
}
