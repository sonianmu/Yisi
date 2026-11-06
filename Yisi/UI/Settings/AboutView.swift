import SwiftUI

/// The name and icon, the slogan, then links and the fine print at the foot of the page.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.settingsPageHeight) private var pageHeight

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    private var currentYear: String { String(Calendar.current.component(.year, from: Date())) }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 20) {
                Text("Yisi")
                    .font(.system(size: 60, weight: .ultraLight))
                    .tracking(-1)
                    .foregroundColor(.primary)
                YisiAppIcon(size: 64)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            }
            .padding(.bottom, 16)

            Text("We deserve better things.")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.primary.opacity(0.8))
                .lineLimit(1)
        }
        // Centred above the links and fine print, a little high, where the eye sets the middle.
        .padding(.bottom, 96)
        // A fixed minimum, not Spacers: the scroll view sizes itself to its content.
        .frame(maxWidth: .infinity, minHeight: pageHeight)
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    PageLink(title: "Home".localized) { openURL(URL(string: "https://yisi.pages.dev/")!) }
                    PageLink(title: "GitHub".localized) { openURL(URL(string: "https://github.com/MUTRO888/Yisi")!) }
                    PageLink(title: "Begin".localized) {
                        NotificationCenter.default.post(name: Notification.Name("ShowWelcome"), object: nil)
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("© \(currentYear) Sonian Mu. All rights reserved.")
                    Spacer(minLength: 12)
                    Text("\(appVersion) · GNU GPLv3")
                        .monospacedDigit()
                }
                .font(.system(size: 10, design: .serif))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
        }
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
                .font(.system(size: 12, design: .serif))
                .foregroundColor(.primary)
                .underline(isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
