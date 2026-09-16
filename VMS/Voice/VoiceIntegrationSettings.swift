import Foundation
import Observation
import VMSCore

enum VoiceIntegration: String, CaseIterable, Identifiable {
    case voiceVox = "VOICEVOX"
    case aiVoice2 = "A.I.VOICE2"
    case aquesTalkPlayer = "AquesTalk Player"
    case macSystemVoice = "macOS音声"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voiceVox: "VOICEVOX"
        case .aiVoice2: "A.I.VOICE2"
        case .aquesTalkPlayer: "AquesTalk Player"
        case .macSystemVoice: "Mac音声"
        }
    }

    var settingsKey: String {
        switch self {
        case .voiceVox: "voiceIntegration.enabled.voicevox"
        case .aiVoice2: "voiceIntegration.enabled.aivoice2"
        case .aquesTalkPlayer: "voiceIntegration.enabled.aquestalkPlayer"
        case .macSystemVoice: "voiceIntegration.enabled.macSystemVoice"
        }
    }

    var detail: String {
        switch self {
        case .voiceVox: "ローカルエンジンへ接続して話者・スタイルを使用します。"
        case .aiVoice2: "製品画面から話者を読み取り、直接生成します。"
        case .aquesTalkPlayer: "公式Mac版のプリセットを読み取り、WAVを生成します。"
        case .macSystemVoice: "macOSに入っている日本語音声を使用します。"
        }
    }

    static func from(providerID: String) -> VoiceIntegration? {
        switch providerID {
        case "VOICEVOX": .voiceVox
        case "A.I.VOICE2": .aiVoice2
        case AquesTalkPlayerSupport.providerID: .aquesTalkPlayer
        case MacSystemVoiceSupport.providerID: .macSystemVoice
        default: nil
        }
    }
}

@Observable
@MainActor
final class VoiceIntegrationSettings {
    private let defaults: UserDefaults

    var voiceVoxEnabled: Bool { didSet { save(.voiceVox, voiceVoxEnabled) } }
    var aiVoice2Enabled: Bool { didSet { save(.aiVoice2, aiVoice2Enabled) } }
    var aquesTalkPlayerEnabled: Bool { didSet { save(.aquesTalkPlayer, aquesTalkPlayerEnabled) } }
    var macSystemVoiceEnabled: Bool { didSet { save(.macSystemVoice, macSystemVoiceEnabled) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        voiceVoxEnabled = Self.read(.voiceVox, from: defaults)
        aiVoice2Enabled = Self.read(.aiVoice2, from: defaults)
        aquesTalkPlayerEnabled = Self.read(.aquesTalkPlayer, from: defaults)
        macSystemVoiceEnabled = Self.read(.macSystemVoice, from: defaults)
    }

    func isEnabled(_ integration: VoiceIntegration) -> Bool {
        switch integration {
        case .voiceVox: voiceVoxEnabled
        case .aiVoice2: aiVoice2Enabled
        case .aquesTalkPlayer: aquesTalkPlayerEnabled
        case .macSystemVoice: macSystemVoiceEnabled
        }
    }

    func isEnabled(providerID: String) -> Bool {
        guard let integration = VoiceIntegration.from(providerID: providerID) else { return false }
        return isEnabled(integration)
    }

    var enabledIntegrations: [VoiceIntegration] {
        VoiceIntegration.allCases.filter(isEnabled)
    }

    var firstEnabledProviderID: String? { enabledIntegrations.first?.rawValue }

    private static func read(_ integration: VoiceIntegration, from defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: integration.settingsKey) != nil else { return true }
        return defaults.bool(forKey: integration.settingsKey)
    }

    private func save(_ integration: VoiceIntegration, _ enabled: Bool) {
        defaults.set(enabled, forKey: integration.settingsKey)
    }
}
