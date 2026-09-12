import Foundation

/// Reads/writes a project as a directory package:
///
///     MyProject.VMS/
///         project.json
///         Assets/          (synthesized voice WAVs, imported character images)
///
/// A directory rather than a single file because the project references asset files by
/// name — bundling them together is what makes the package portable/movable as one unit.
public enum ProjectPackage {
    public static let fileExtension = "VMS"

    public enum PackageError: Error, LocalizedError {
        case notAPackage(URL)

        public var errorDescription: String? {
            switch self {
            case .notAPackage(let url):
                return "\(url.lastPathComponent) はプロジェクトパッケージではありません。"
            }
        }
    }

    /// Writes `project` and copies the contents of `assetsDirectory` into `packageURL`.
    /// Overwrites whatever was previously at `packageURL`.
    public static func write(project: Project, assetsDirectory: URL, to packageURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: packageURL.appendingPathComponent("project.json"))

        let destinationAssets = packageURL.appendingPathComponent("Assets", isDirectory: true)
        try fileManager.createDirectory(at: destinationAssets, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: assetsDirectory.path) {
            let items = try fileManager.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil)
            for item in items {
                let destination = destinationAssets.appendingPathComponent(item.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: item, to: destination)
            }
        }
    }

    /// Returns the decoded project plus the URL of its `Assets` folder (asset file names
    /// in the project are relative to this).
    public static func read(from packageURL: URL) throws -> (project: Project, assetsDirectory: URL) {
        let projectFileURL = packageURL.appendingPathComponent("project.json")
        guard FileManager.default.fileExists(atPath: projectFileURL.path) else {
            throw PackageError.notAPackage(packageURL)
        }
        let data = try Data(contentsOf: projectFileURL)
        let project = try JSONDecoder().decode(Project.self, from: data)
        let assetsDirectory = packageURL.appendingPathComponent("Assets", isDirectory: true)
        return (project, assetsDirectory)
    }
}
