import AppKit
import SwiftUI

final class AppDialogWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func make<Content: View>(content: Content, size: CGSize) -> AppDialogWindow {
        let window = AppDialogWindow(contentRect: CGRect(origin: .zero, size: size),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.contentView = NSHostingView(rootView: content)
        window.setContentSize(size)
        window.center()
        return window
    }
}

struct DialogSurface<Content: View>: View {
    @AppStorage(AppDefaults.Keys.appTheme) private var appTheme = AppDefaults.appTheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(ThemeBackground())
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .preferredColorScheme(ColorScheme(from: appTheme))
    }
}

struct DialogActionButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: primary ? .medium : .regular, design: .serif))
                .foregroundStyle(primary ? AppColors.onAccent : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(primary ? AppColors.primary : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

final class AppAlert {
    enum Style { case informational, success, warning }

    var messageText = ""
    var informativeText = ""
    var alertStyle = Style.informational
    var defaultButtonIndex = 0
    private var titles: [String] = []

    func addButton(withTitle title: String) {
        titles.append(title)
    }

    @discardableResult
    func runModal() -> NSApplication.ModalResponse {
        let labels = titles.isEmpty ? ["OK".localized] : titles
        let content = AppAlertContent(title: messageText, message: informativeText,
                                      symbol: alertStyle == .warning ? "exclamationmark.circle" : alertStyle == .success ? "checkmark.circle" : "info.circle",
                                      buttons: labels, defaultButtonIndex: defaultButtonIndex) { index in
            NSApp.stopModal(withCode: index < 0 ? .abort : NSApplication.ModalResponse(rawValue: 1000 + index))
        }
        let hosting = NSHostingView(rootView: content)
        let window = AppDialogWindow.make(content: content, size: hosting.fittingSize)
        window.title = messageText
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: window)
        window.orderOut(nil)
        return response
    }
}

private struct AppAlertContent: View {
    let title: String
    let message: String
    let symbol: String
    let buttons: [String]
    let defaultButtonIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        DialogSurface {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(AppColors.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    ForEach(Array(buttons.enumerated().reversed()), id: \.offset) { index, title in
                        DialogActionButton(title: title, primary: index == 0) { onSelect(index) }
                            .keyboardShortcut(index == defaultButtonIndex ? KeyboardShortcut.defaultAction : nil)
                    }
                }
            }
            .padding(24)
            .frame(width: 380, alignment: .leading)
        }
        .onExitCommand { onSelect(-1) }
    }
}
