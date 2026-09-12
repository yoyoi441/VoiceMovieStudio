import Foundation

public struct CreditMetadata: Codable, Hashable, Sendable {
    public var title: String
    public var creator: String
    public var sourceURL: String
    public var licenseName: String
    public var licenseURL: String
    public var note: String

    public init(title: String = "", creator: String = "", sourceURL: String = "", licenseName: String = "", licenseURL: String = "", note: String = "") {
        self.title = title
        self.creator = creator
        self.sourceURL = sourceURL
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.note = note
    }
}
