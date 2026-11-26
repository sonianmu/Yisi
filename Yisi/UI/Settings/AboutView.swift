import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.settingsPageHeight) private var pageHeight

    private var currentYear: String { String(Calendar.current.component(.year, from: Date())) }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    YisiWordmark(size: 60, isLight: true)
                        .foregroundColor(.primary)
                    YisiAppIcon(size: 64)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                }

                Text("We deserve better things.")
                    .font(.yisi(22, weight: .light))
                    .foregroundColor(.primary.opacity(0.8))
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    PageLink(title: "Home".localized) { openURL(URL(string: "https://yisi.pages.dev/")!) }
                    PageLink(title: "GitHub".localized) { openURL(URL(string: "https://github.com/MUTRO888/Yisi")!) }
                    PageLink(title: "Begin".localized) {
                        NotificationCenter.default.post(name: Notification.Name("ShowWelcome"), object: nil)
                    }
                }
                Text("© \(currentYear) Sonian Mu. All rights reserved.")
                    .font(.yisi(10))
                    .foregroundColor(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: pageHeight)
    }
}

/// A plain serif text link, underlined on hover.
private struct PageLink: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.yisi(12))
                .foregroundColor(.primary)
                .underline(isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
