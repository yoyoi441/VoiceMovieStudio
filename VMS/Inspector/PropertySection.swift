import SwiftUI

/// §7: a collapsible group of property controls, with its expanded/collapsed state
/// remembered per section title across launches (`UserDefaults`), per spec "各セクショ
/// ンの開閉状態は、可能ならユーザー設定として保持します".
struct PropertySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool

    init(_ title: String, defaultExpanded: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
        let key = Self.defaultsKey(for: title)
        if let stored = UserDefaults.standard.object(forKey: key) as? Bool {
            _isExpanded = State(initialValue: stored)
        } else {
            _isExpanded = State(initialValue: defaultExpanded)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
                UserDefaults.standard.set(isExpanded, forKey: Self.defaultsKey(for: title))
            } label: {
                HStack(spacing: 4) {
                    IconCatalog.resolve(isExpanded ? .chevronExpanded : .chevronCollapsed)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(title).font(Theme.labelFont).bold()
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(title)セクション"))
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                .padding(.leading, 13)
            }
        }
    }

    private static func defaultsKey(for title: String) -> String {
        "PropertySection.expanded.\(title)"
    }
}
