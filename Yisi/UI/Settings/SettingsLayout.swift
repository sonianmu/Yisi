import SwiftUI

enum SettingsLayout {
    static let inset: CGFloat = 16
    static let contentWidth: CGFloat = 560
    /// Space between groups; rows inside a group sit `rowSpacing` apart.
    static let sectionSpacing: CGFloat = 22
    static let rowSpacing: CGFloat = 2
    /// Every row is this tall, whatever its control, so rows keep one even rhythm.
    static let controlHeight: CGFloat = 30
    static let fieldWidth: CGFloat = 150
    /// Labels share the page's left edge; controls start on one column after the longest label.
    static let labelMaxWidth: CGFloat = 132
    static let axisGap: CGFloat = 20
}

extension View {
    func settingsTextField() -> some View {
        textFieldStyle(.plain)
            .font(.yisi(13))
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(AppColors.primary.opacity(0.05))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.primary.opacity(0.1), lineWidth: 0.5))
    }

    /// Lines up every `SettingsRow` inside on one axis, as wide as the longest label allows.
    func settingsForm() -> some View { modifier(SettingsFormAxis()) }
}

extension EnvironmentValues {
    @Entry var settingsLabelWidth: CGFloat?
}

private struct SettingsLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SettingsFormAxis: ViewModifier {
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .environment(\.settingsLabelWidth, width)
            .onPreferenceChange(SettingsLabelWidthKey.self) { measured in
                width = measured > 0 ? min(ceil(measured), SettingsLayout.labelMaxWidth) : nil
            }
    }
}

/// A label on the form axis with its control beside it. An optional caption sits under the control.
struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    private let control: Control
    @Environment(\.settingsLabelWidth) private var labelWidth

    init(title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayout.axisGap) {
            Text(title)
                .font(.yisi(13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: labelWidth, alignment: .leading)
                .frame(minHeight: SettingsLayout.controlHeight)
                .background(alignment: .leading) {
                    Text(title).font(.yisi(13)).fixedSize().hidden()
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: SettingsLabelWidthKey.self, value: proxy.size.width)
                        })
                }
                .accessibilityLabeledPair(role: .label, id: title, in: accessibilityNamespace)

            VStack(alignment: .leading, spacing: 4) {
                control
                    .frame(minHeight: SettingsLayout.controlHeight)
                    .accessibilityLabeledPair(role: .content, id: title, in: accessibilityNamespace)
                if let detail {
                    SettingsCaption(detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @Namespace private var accessibilityNamespace
}

/// Content that belongs in the control column without a label of its own (an action, a note).
struct SettingsAxisContent<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.settingsLabelWidth) private var labelWidth

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayout.axisGap) {
            Color.clear.frame(width: labelWidth ?? 0, height: 1)
            VStack(alignment: .leading, spacing: 4, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsCaption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.yisi(11))
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing, content: content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The shortcut field shared by both global shortcuts.
struct SettingsShortcutControl: View {
    let shortcut: String
    let isRecording: Bool
    let showHint: Bool
    let record: () -> Void
    let reset: () -> Void

    var body: some View {
        Button(action: record) {
            HStack {
                if isRecording {
                    Text(showHint ? "Requires Cmd/Ctrl/Opt".localized : "Press keys...".localized)
                        .font(.yisi(13))
                        .foregroundColor(showHint ? .orange : .accentColor)
                    Spacer()
                    Image(systemName: "record.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse)
                } else {
                    Text(shortcut.isEmpty ? "Record Shortcut".localized : shortcut)
                        .font(.yisi(13))
                        .foregroundColor(.primary)
                    Spacer()
                    if !shortcut.isEmpty {
                        Button(action: reset) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear Shortcut".localized)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(width: 160)
            .background(isRecording ? AppColors.primary.opacity(0.1) : AppColors.primary.opacity(0.05))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isRecording ? AppColors.primary.opacity(0.3) : AppColors.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The outlined button General has always used for Check for Updates and Customize Popup Layout.
struct OutlinedButton: View {
    let title: String
    var size: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.yisi(size))
                .foregroundColor(.primary)
                .padding(.horizontal, size < 13 ? 10 : 12)
                .padding(.vertical, size < 13 ? 5 : 6)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
