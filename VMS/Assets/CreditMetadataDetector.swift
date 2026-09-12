import Foundation
import VMSCore

enum CreditMetadataDetector {
    static func detect(for sourceURL: URL) -> CreditMetadata {
        var credit = CreditMetadata(title: sourceURL.deletingPathExtension().lastPathComponent)
        let directory = sourceURL.hasDirectoryPath ? sourceURL : sourceURL.deletingLastPathComponent()
        for name in ["credit.json", "credits.json", "attribution.json"] {
            let url = directory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(CreditMetadata.self, from: data) {
                return decoded.title.isEmpty ? CreditMetadata(title: credit.title, creator: decoded.creator, sourceURL: decoded.sourceURL, licenseName: decoded.licenseName, licenseURL: decoded.licenseURL, note: decoded.note) : decoded
            }
        }
        if let license = MaterialFileClassifier.childFiles(directory).first(where: { $0.lastPathComponent.lowercased().hasPrefix("license") || $0.lastPathComponent.lowercased().hasPrefix("readme") }),
           let text = try? String(contentsOf: license, encoding: .utf8) {
            credit.note = String(text.prefix(500)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return credit
    }
}
