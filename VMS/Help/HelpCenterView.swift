import SwiftUI

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = HelpContent.topics.first?.id

    private var filtered: [HelpTopic] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? HelpContent.topics : HelpContent.topics.filter { $0.searchableText.localizedCaseInsensitiveContains(value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ヘルプセンター").font(.title2).bold()
                Spacer()
                Button("チュートリアルを開く") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        NotificationCenter.default.post(name: .showTutorial, object: nil)
                    }
                }
                Button("閉じる") { dismiss() }
            }
            .padding()
            Divider()
            NavigationSplitView {
                List(filtered, selection: $selection) { topic in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.title)
                            Text(topic.category).font(.caption2).foregroundColor(.secondary)
                        }
                    } icon: { Image(systemName: topic.symbol) }
                    .tag(topic.id)
                }
                .searchable(text: $query, prompt: "操作や問題を検索")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } detail: {
                if let topic = HelpContent.topics.first(where: { $0.id == selection }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Label(topic.title, systemImage: topic.symbol).font(.title2).bold()
                            Text(topic.summary).foregroundColor(.secondary)
                            ForEach(Array(topic.sections.enumerated()), id: \.offset) { _, section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title).font(.headline)
                                    Text(section.body).textSelection(.enabled)
                                }
                                Divider()
                            }
                        }
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(28)
                    }
                } else {
                    ContentUnavailableView("項目を選択してください", systemImage: "questionmark.circle")
                }
            }
        }
        .frame(width: 940, height: 650)
        .onChange(of: filtered.map(\.id)) { _, ids in
            if let selection, ids.contains(selection) { return }
            selection = ids.first
        }
    }
}

extension Notification.Name {
    static let showTutorial = Notification.Name("showTutorial")
}
