import Foundation

public enum SofTalkSupport {
    public static let providerID = "SofTalk"

    public enum BuiltInProfile: String, CaseIterable, Codable, Identifiable, Sendable {
        case reimu
        case marisa

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .reimu: "ゆっくり霊夢"
            case .marisa: "ゆっくり魔理沙"
            }
        }
    }

    public struct Profile: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        public var displayName: String
        public var isConfigured: Bool

        public init(id: String, displayName: String, isConfigured: Bool) {
            self.id = id
            self.displayName = displayName
            self.isConfigured = isConfigured
        }
    }

    public struct BridgeInfo: Codable, Hashable, Sendable {
        public var status: String
        public var product: String
        public var bridgeVersion: Int
        public var profiles: [Profile]

        public init(status: String, product: String, bridgeVersion: Int, profiles: [Profile]) {
            self.status = status
            self.product = product
            self.bridgeVersion = bridgeVersion
            self.profiles = profiles
        }
    }

    public struct SynthesisRequest: Codable, Hashable, Sendable {
        public var text: String
        public var profileID: String
        public var settings: VoiceSettings

        public init(text: String, profileID: String, settings: VoiceSettings) {
            self.text = text
            self.profileID = profileID
            self.settings = settings.validatedForSofTalk()
        }
    }

    public static var builtInProfiles: [Profile] {
        BuiltInProfile.allCases.map {
            Profile(id: $0.id, displayName: $0.displayName, isConfigured: false)
        }
    }

    public static func displayName(for profileID: String) -> String {
        BuiltInProfile(rawValue: profileID)?.displayName ?? profileID
    }
}

public extension VoiceSettings {
    static var sofTalkDefault: VoiceSettings {
        VoiceSettings(volume: 1, pitch: 1, speed: 1, intonation: 1)
    }

    func validatedForSofTalk() -> VoiceSettings {
        var result = self
        result.volume = Self.clampFinite(result.volume, to: 0...2, fallback: 1)
        result.pan = Self.clampFinite(result.pan, to: -1...1, fallback: 0)
        result.pitch = Self.clampFinite(result.pitch, to: 0.5...2, fallback: 1)
        result.speed = Self.clampFinite(result.speed, to: 0.5...2, fallback: 1)
        result.intonation = Self.clampFinite(result.intonation, to: 0...2, fallback: 1)
        result.preSilence = Self.clampFinite(result.preSilence, to: 0...5, fallback: 0.1)
        result.postSilence = Self.clampFinite(result.postSilence, to: 0...5, fallback: 0.1)
        result.styleWeights = nil
        return result
    }

    private static func clampFinite(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
