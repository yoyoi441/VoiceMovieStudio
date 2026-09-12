import SwiftUI

/// §7-3 "フォント" — a tabbed picker ("すべて"/"お気に入り"/"最近使った") over every font
/// family installed on the Mac (`FontCatalog.allFamilyNames`), replacing free-text font
/// name entry. Each row renders its own name in that font for a live preview.
struct FontPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let currentFontName: String
    let onSelect: (String) -> Void

    private enum Tab: String, CaseIterable {
        case all = "すべて"
        case favorites = "お気に入り"
        case recent = "最近使った"
    }

    @State private var tab: Tab = .all
    @State private var searchText = ""
    @State private var favorites = FontUsageStore.favorites

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("フォントを選択").font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }
            }
            .padding([.top, .horizontal])
            .padding(.bottom, 8)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)

            TextField("フォント名で検索", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.top, 8)

            Divider().padding(.top, 8)

            if filteredFamilies.isEmpty {
                Spacer()
                Text(emptyMessage).font(.caption).foregroundColor(.secondary)
                Spacer()
            } else {
                List(filteredFamilies, id: \.self) { family in
                    row(for: family)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 420, height: 480)
    }

    private var emptyMessage: String {
        switch tab {
        case .all: return "見つかりませんでした"
        case .favorites: return "お気に入りに追加したフォントがここに表示されます"
        case .recent: return "最近使ったフォントがここに表示されます"
        }
    }

    private var filteredFamilies: [String] {
        let base: [String]
        switch tab {
        case .all:
            base = FontCatalog.allFamilyNames
        case .favorites:
            base = FontCatalog.allFamilyNames.filter { favorites.contains($0) }
        case .recent:
            let installed = Set(FontCatalog.allFamilyNames)
            base = FontUsageStore.recents.filter { installed.contains($0) }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private func row(for family: String) -> some View {
        HStack(spacing: 8) {
            Button {
                FontUsageStore.toggleFavorite(family)
                favorites = FontUsageStore.favorites
            } label: {
                Image(systemName: favorites.contains(family) ? "star.fill" : "star")
                    .foregroundColor(favorites.contains(family) ? .yellow : .secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(favorites.contains(family) ? "お気に入りから削除" : "お気に入りに追加"))

            Text(family)
                .font(.custom(family, size: 15))
                .lineLimit(1)

            Spacer()

            if family == currentFontName {
                Image(systemName: "checkmark").foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            FontUsageStore.recordUsed(family)
            onSelect(family)
            dismiss()
        }
    }
}
