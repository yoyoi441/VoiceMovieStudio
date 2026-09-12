import SwiftUI
import VMSCore

/// §7-3. Every styling control here is multi-select-aware (via `store.mixedBinding`/
/// `numericBinding`, generic over `Clip`), so adjusting e.g. font size with several text
/// clips selected changes all of them. The text *content* itself is the one exception —
/// bulk-editing prose across clips isn't meaningful, so that field only shows up when
/// exactly one text clip is selected.
struct TextClipInspector: View {
    @Environment(ProjectStore.self) private var store
    let primary: Clip
    let isMultiSelect: Bool

    @State private var showFontPicker = false
    @State private var subtitleProfiles = SubtitleProfileStore.shared
    @State private var newProfileName = ""

    var body: some View {
        guard case .text(let data) = primary.content else { return AnyView(EmptyView()) }

        return AnyView(
            PropertySection("テキスト") {
                HStack(spacing: 6) {
                    Text("字幕プロファイル").font(Theme.labelFont).foregroundColor(.secondary)
                    Menu("適用") {
                        ForEach(subtitleProfiles.profiles) { profile in
                            Button(profile.name) { store.applySubtitleProfile(profile) }
                        }
                    }
                    TextField("新しい名前", text: $newProfileName).textFieldStyle(.roundedBorder)
                    Button("保存") {
                        subtitleProfiles.save(name: newProfileName, from: data, effects: primary.effects)
                        newProfileName = ""
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                TogglePropertyControl(label: "字幕を表示する", value: mixed({ $0.isVisible }, { $0.isVisible = $1 }))

                if !isMultiSelect {
                    TextEditor(text: textBinding(data))
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border))
                }

                HStack(spacing: 6) {
                    Text("フォント").font(Theme.labelFont).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                    Button {
                        showFontPicker = true
                    } label: {
                        HStack {
                            Text(data.fontName.isEmpty ? "システムフォント" : data.fontName)
                                .font(fontPreviewFont(data.fontName))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .sheet(isPresented: $showFontPicker) {
                    FontPickerView(currentFontName: data.fontName) { newName in
                        applyFont(newName)
                    }
                }

                NumericPropertyControl(label: "文字サイズ", value: numeric({ $0.fontSize }, { $0.fontSize = max(1, $1) }), range: 8...300, unit: "pt")
                NumericPropertyControl(label: "行の高さ", value: numeric({ $0.lineHeight }, { $0.lineHeight = max(0.5, $1) }), range: 0.5...3, decimalPlaces: 2, resetValue: 1)
                NumericPropertyControl(label: "文字間隔", value: numeric({ $0.letterSpacing }, { $0.letterSpacing = $1 }), range: -10...50, resetValue: 0)

                SelectPropertyControl(
                    label: "折り返し方法",
                    value: mixed({ $0.wrapMode }, { $0.wrapMode = $1 }),
                    options: TextWrapMode.allCases.map { ($0, $0.displayName) }
                )
                NumericPropertyControl(label: "折り返し幅", value: numeric({ $0.wrapWidth }, { $0.wrapWidth = max(50, $1) }), range: 50...1920, unit: "pt")
                SelectPropertyControl(
                    label: "文字揃え",
                    value: mixed({ $0.alignment }, { $0.alignment = $1 }),
                    options: TextHorizontalAlignment.allCases.map { ($0, $0.displayName) }
                )

                ColorPropertyControl(label: "文字色", value: colorMixed({ $0.color }, { $0.color = $1 }))
                ColorPropertyControl(label: "装飾色", value: colorMixed({ $0.decorationColor }, { $0.decorationColor = $1 }))

                TogglePropertyControl(label: "太字", value: mixed({ $0.isBold }, { $0.isBold = $1 }))
                TogglePropertyControl(label: "イタリック", value: mixed({ $0.isItalic }, { $0.isItalic = $1 }))
                TogglePropertyControl(label: "下線", value: mixed({ $0.isUnderlined }, { $0.isUnderlined = $1 }))
                TogglePropertyControl(label: "打ち消し線", value: mixed({ $0.isStrikethrough }, { $0.isStrikethrough = $1 }))
                TogglePropertyControl(label: "行末スペース削除", value: mixed({ $0.trimTrailingSpace }, { $0.trimTrailingSpace = $1 }))

                Divider()
                Text("文字ごとの表示アニメーション(未対応)").font(.caption2).foregroundColor(.secondary)
                TogglePropertyControl(label: "文字ごとに分割", value: mixed({ $0.splitPerCharacter }, { $0.splitPerCharacter = $1 }))
                NumericPropertyControl(label: "表示間隔", value: numeric({ $0.revealInterval }, { $0.revealInterval = max(0, $1) }), range: 0...1, decimalPlaces: 2, unit: "秒")
                SelectPropertyControl(label: "表示方向", value: mixed({ $0.revealDirection }, { $0.revealDirection = $1 }), options: RevealDirection.allCases.map { ($0, $0.displayName) })
                NumericPropertyControl(label: "非表示間隔", value: numeric({ $0.concealInterval }, { $0.concealInterval = max(0, $1) }), range: 0...1, decimalPlaces: 2, unit: "秒")
                SelectPropertyControl(label: "非表示方向", value: mixed({ $0.concealDirection }, { $0.concealDirection = $1 }), options: RevealDirection.allCases.map { ($0, $0.displayName) })
            }
        )
    }

    private func textBinding(_ data: TextClipData) -> Binding<String> {
        Binding(
            get: { data.text },
            set: { newValue in
                var updated = primary
                guard case .text(var d) = updated.content else { return }
                d.text = newValue
                updated.content = .text(d)
                store.updateClip(updated)
            }
        )
    }

    private func fontPreviewFont(_ name: String) -> Font {
        name.isEmpty ? .system(size: 13) : .custom(name, size: 13)
    }

    /// Applies the picked font family across every selected text clip (one undo step),
    /// same as every other bulk-editable field in this inspector.
    private func applyFont(_ name: String) {
        mixed({ $0.fontName }, { $0.fontName = $1 }).wrappedValue = name
    }

    private func numeric(_ get: @escaping (TextClipData) -> Double, _ set: @escaping (inout TextClipData, Double) -> Void) -> Binding<Double?> {
        store.numericBinding(
            get: { clip in guard case .text(let d) = clip.content else { return 0 }; return get(d) },
            set: { clip, newValue in
                guard case .text(var d) = clip.content else { return }
                set(&d, newValue)
                clip.content = .text(d)
            }
        )
    }

    /// `uniformKind` in `InspectorView` guarantees every selected clip is `.text` while
    /// this view is shown, so the non-text fallback branch below is unreachable in
    /// practice — it only exists to satisfy the type checker's need for *some* `V`.
    private func mixed<V: Equatable>(_ get: @escaping (TextClipData) -> V, _ set: @escaping (inout TextClipData, V) -> Void) -> Binding<V?> {
        store.mixedBinding(
            get: { clip in
                guard case .text(let d) = clip.content else { return get(TextClipData(text: "")) }
                return get(d)
            },
            set: { clip, newValue in
                guard case .text(var d) = clip.content else { return }
                set(&d, newValue)
                clip.content = .text(d)
            }
        )
    }

    private func colorMixed(_ get: @escaping (TextClipData) -> CodableColor, _ set: @escaping (inout TextClipData, CodableColor) -> Void) -> Binding<CodableColor?> {
        store.mixedBinding(
            get: { clip in guard case .text(let d) = clip.content else { return .white }; return get(d) },
            set: { clip, newValue in
                guard case .text(var d) = clip.content else { return }
                set(&d, newValue)
                clip.content = .text(d)
            }
        )
    }
}
