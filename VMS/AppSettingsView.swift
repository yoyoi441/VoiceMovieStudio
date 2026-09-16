import SwiftUI
import VMSCore

struct AppSettingsView: View {
    @Environment(ProjectStore.self) private var store
    @AppStorage(AquesTalkPlayerSettings.licenseAcknowledgedKey) private var aquesTalkLicenseAcknowledged = false

    var body: some View {
        @Bindable var integrations = store.voiceIntegrations

        Form {
            Section("音声連携") {
                integrationToggle(
                    "VOICEVOX",
                    detail: VoiceIntegration.voiceVox.detail,
                    isOn: $integrations.voiceVoxEnabled
                )
                integrationToggle(
                    "A.I.VOICE2",
                    detail: VoiceIntegration.aiVoice2.detail,
                    isOn: $integrations.aiVoice2Enabled
                )
                integrationToggle(
                    "AquesTalk Player",
                    detail: VoiceIntegration.aquesTalkPlayer.detail,
                    isOn: $integrations.aquesTalkPlayerEnabled
                )
                integrationToggle(
                    "Mac音声",
                    detail: VoiceIntegration.macSystemVoice.detail,
                    isOn: $integrations.macSystemVoiceEnabled
                )
                Text("オフにした連携は音声パネルと新しいキャラクター設定の候補から隠れます。既存プロジェクトの設定値や生成済み音声は削除されません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AquesTalk Playerの利用条件") {
                Toggle("公式の利用条件を理解しました", isOn: $aquesTalkLicenseAcknowledged)
                Text(AquesTalkPlayerSupport.commercialUseNotice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack {
                    Link("公式の利用条件", destination: URL(string: AquesTalkPlayerSupport.officialPageURL)!)
                    Link("使用ライセンス", destination: URL(string: AquesTalkPlayerSupport.licenseStoreURL)!)
                }
                .font(.caption)
                Text("確認をオフにすると、AquesTalk Playerによる新しい音声生成を停止し、音声パネルへ確認欄を再表示します。ライセンスキーは公式アプリ側だけで管理します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 620, height: 520)
    }

    private func integrationToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: isOn)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
        }
    }
}
