import Foundation
import AppKit
import SwiftUI

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var progressStatus: String = ""

    private let owner = "sonianmu"
    private let repo = "Yisi"
    private var progressWindow: NSWindow?
    private var updateAlertWindow: NSWindow?
    private var automaticCheckObserver: NSObjectProtocol?
    private lazy var automaticScheduler = AutomaticUpdateScheduler { [weak self] in
        self?.checkForUpdates(silent: true)
    }

    private static let alertedVersionKey = "update_alerted_version"
    private static let alertedForCurrentKey = "update_alerted_for_current"

    private var alertedVersion: String? {
        get { UserDefaults.standard.string(forKey: Self.alertedVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.alertedVersionKey) }
    }
    private var alertedForCurrent: String? {
        get { UserDefaults.standard.string(forKey: Self.alertedForCurrentKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.alertedForCurrentKey) }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private init() {}

    /// Start once per app session. Preference changes only manage the timer;
    /// enabling it starts a fresh six-hour interval without an extra immediate check.
    func startAutomaticChecks() {
        guard automaticCheckObserver == nil else { return }
        automaticCheckObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.automaticScheduler.setEnabled(UserDefaults.standard.bool(forKey: AppDefaults.Keys.autoCheckUpdates))
        }
        let enabled = UserDefaults.standard.bool(forKey: AppDefaults.Keys.autoCheckUpdates)
        automaticScheduler.setEnabled(enabled)
        if enabled { checkForUpdates(silent: true) }
    }

    deinit {
        if let automaticCheckObserver { NotificationCenter.default.removeObserver(automaticCheckObserver) }
    }

    // MARK: - Check

    func checkForUpdates(silent: Bool = true) {
        guard !isChecking else { return }
        isChecking = true

        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result = Result { try UpdateRelease.decode(data: data, response: response, error: error) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                // A request already in flight must not show an automatic alert
                // after the user switches automatic updates off. Manual checks remain available.
                guard !silent || UserDefaults.standard.bool(forKey: AppDefaults.Keys.autoCheckUpdates) else { return }

                guard case .success(let release) = result else {
                    self.latestVersion = nil
                    self.updateAvailable = false
                    if !silent { self.showCheckFailure() }
                    return
                }

                let remote = release.version
                self.latestVersion = remote

                if release.isNewer(than: self.currentVersion) {
                    self.updateAvailable = true
                    let alreadyAlerted = self.alertedVersion == remote
                        && self.alertedForCurrent == self.currentVersion
                    if silent && alreadyAlerted { return }
                    self.alertedVersion = remote
                    self.alertedForCurrent = self.currentVersion
                    self.showUpdateAlert(version: remote, htmlURL: release.html_url.absoluteString,
                                         dmgURL: release.dmgURL?.absoluteString, releaseNotes: release.body ?? "")
                } else {
                    self.updateAvailable = false
                    if !silent { self.showUpToDate() }
                }
            }
        }.resume()
    }

    // MARK: - Alerts

    private func showUpdateAlert(version: String, htmlURL: String, dmgURL: String?, releaseNotes: String,
                                 updateAction: (() -> Void)? = nil) {
        guard updateAlertWindow == nil, progressWindow == nil else { return }

        let cleanedNotes = cleanMarkdown(releaseNotes)
        let hasDMG = dmgURL != nil

        let view = UpdateAlertView(
                newVersion: version,
                currentVersion: currentVersion,
                releaseNotes: cleanedNotes,
                hasDMG: hasDMG,
                onLater: { [weak self] in
                    self?.closeUpdateAlertWindow()
                },
                onUpdate: { [weak self] in
                    self?.closeUpdateAlertWindow()
                    if let updateAction {
                        updateAction()
                        return
                    }
                    if let dmgURL {
                        self?.downloadAndInstall(dmgURL: dmgURL, htmlURL: htmlURL)
                    } else if let url = URL(string: htmlURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        let window = AppDialogWindow.make(content: view, size: CGSize(width: 360, height: 340))
        window.title = "Update Available".localized
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateAlertWindow = window
    }

    private func closeUpdateAlertWindow() {
        let window = updateAlertWindow
        updateAlertWindow = nil
        DispatchQueue.main.async {
            window?.orderOut(nil)
        }
    }

    private func showUpToDate() {
        let alert = AppAlert()
        alert.messageText = "You're up to date".localized
        alert.informativeText = String(
            format: "Yisi %@ is the latest version.".localized,
            "v\(currentVersion)"
        )
        alert.alertStyle = .success
        alert.addButton(withTitle: "OK".localized)
        alert.runModal()
    }

    private func showError(fallbackURL: String?) {
        closeProgressWindow()
        let alert = AppAlert()
        alert.messageText = "Update Failed".localized
        alert.informativeText = "Auto update failed. You can download manually from GitHub.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Download".localized)
        alert.addButton(withTitle: "OK".localized)

        if alert.runModal() == .alertFirstButtonReturn, let fallbackURL,
           let url = URL(string: fallbackURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Progress Window

    private func showCheckFailure() {
        let alert = AppAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't check for updates".localized
        alert.informativeText = "The update service could not be reached. Please try again or check GitHub Releases.".localized
        alert.addButton(withTitle: "OK".localized)
        alert.addButton(withTitle: "GitHub Releases".localized)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "https://github.com/sonianmu/Yisi/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showProgressWindow() {
        let window = AppDialogWindow.make(content: UpdateProgressView(manager: self),
                                          size: CGSize(width: 320, height: 156))
        window.title = "Auto Update".localized
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        progressWindow = window
    }

    private func closeProgressWindow() {
        progressWindow?.close()
        progressWindow = nil
    }

    #if DEBUG
    func previewDialog(_ kind: String) {
        switch kind {
        case "available":
            let notes = Array(repeating: "新增可选的 Apple 原生 Liquid Glass，支持翻译弹窗、设置及历史记录。\n配色浮层和高级自定义跟随玻璃开关、染色与深浅模式。\n修复引导页按钮的点击范围。", count: 4).joined(separator: "\n\n")
            showUpdateAlert(version: "1.3.11", htmlURL: "https://github.com/sonianmu/Yisi/releases/latest",
                            dmgURL: "https://github.com/sonianmu/Yisi/releases/download/v1.3.11/Yisi.dmg",
                            releaseNotes: notes) { [weak self] in
                self?.progressStatus = "Downloading...".localized
                self?.showProgressWindow()
            }
        case "downloading", "installing", "restarting":
            progressStatus = (kind == "downloading" ? "Downloading..." : kind == "installing" ? "Installing..." : "Restarting...").localized
            showProgressWindow()
        case "check-error": showCheckFailure()
        case "install-error": showError(fallbackURL: nil)
        default: showUpToDate()
        }
    }
    #endif

    // MARK: - Download & Install

    private func downloadAndInstall(dmgURL: String, htmlURL: String) {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            showError(fallbackURL: htmlURL)
            return
        }

        progressStatus = "Downloading...".localized
        showProgressWindow()

        guard let url = URL(string: dmgURL) else {
            showError(fallbackURL: htmlURL)
            return
        }

        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let tempURL, error == nil else {
                    self.showError(fallbackURL: htmlURL)
                    return
                }
                self.installFromDMG(downloadedURL: tempURL, appPath: appPath, htmlURL: htmlURL)
            }
        }.resume()
    }

    private func installFromDMG(downloadedURL: URL, appPath: String, htmlURL: String) {
        progressStatus = "Installing...".localized

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let dmgPath = NSTemporaryDirectory() + "Yisi_update.dmg"
            let mountPoint = NSTemporaryDirectory() + "yisi_update_mount"
            let stagingPath = NSTemporaryDirectory() + "Yisi_update.app"

            // Cleanup previous attempts
            try? fm.removeItem(atPath: dmgPath)
            try? fm.removeItem(atPath: stagingPath)

            // Move downloaded file to known path
            do {
                try fm.moveItem(atPath: downloadedURL.path, toPath: dmgPath)
            } catch {
                DispatchQueue.main.async { self?.showError(fallbackURL: htmlURL) }
                return
            }

            // Mount DMG
            try? fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
            let mount = Process()
            mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mount.arguments = ["attach", dmgPath, "-nobrowse", "-quiet", "-mountpoint", mountPoint]
            do { try mount.run(); mount.waitUntilExit() } catch {
                self?.cleanup([dmgPath])
                DispatchQueue.main.async { self?.showError(fallbackURL: htmlURL) }
                return
            }
            guard mount.terminationStatus == 0 else {
                self?.cleanup([dmgPath])
                DispatchQueue.main.async { self?.showError(fallbackURL: htmlURL) }
                return
            }

            // Find .app in mounted volume
            let contents = (try? fm.contentsOfDirectory(atPath: mountPoint)) ?? []
            guard let appBundle = contents.first(where: { $0.hasSuffix(".app") }) else {
                self?.detach(mountPoint)
                self?.cleanup([dmgPath])
                DispatchQueue.main.async { self?.showError(fallbackURL: htmlURL) }
                return
            }

            // Copy to staging
            do {
                try fm.copyItem(atPath: "\(mountPoint)/\(appBundle)", toPath: stagingPath)
            } catch {
                self?.detach(mountPoint)
                self?.cleanup([dmgPath])
                DispatchQueue.main.async { self?.showError(fallbackURL: htmlURL) }
                return
            }

            // Only replace Yisi with a valid application bearing the same bundle ID.
            let stagedBundle = Bundle(path: stagingPath)
            guard stagedBundle?.bundleIdentifier == Bundle.main.bundleIdentifier,
                  stagedBundle?.infoDictionary?["CFBundleExecutable"] as? String == "Yisi",
                  PermissionReset.run(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", stagingPath]) else {
                self?.detach(mountPoint)
                self?.cleanup([dmgPath, stagingPath])
                DispatchQueue.main.async { self?.showError(fallbackURL: htmlURL) }
                return
            }

            // Unmount
            self?.detach(mountPoint)

            // Remove quarantine
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-cr", stagingPath]
            try? xattr.run()
            xattr.waitUntilExit()

            // Replace and relaunch
            DispatchQueue.main.async {
                self?.progressStatus = "Restarting...".localized

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/bin/sh")
                    task.arguments = UpdateReplacement.arguments(appPath: appPath, stagingPath: stagingPath, dmgPath: dmgPath)
                    do {
                        try task.run()
                        NSApp.terminate(nil)
                    } catch {
                        self?.showError(fallbackURL: htmlURL)
                    }
                }
            }
        }
    }

    // MARK: - Markdown Cleanup

    private func cleanMarkdown(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { line in
                var l = line
                // Strip heading markers
                while l.hasPrefix("#") { l = String(l.dropFirst()) }
                l = l.trimmingCharacters(in: .whitespaces)
                // Strip blockquote markers
                if l.hasPrefix(">") { l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces) }
                // Strip bold/italic/code inline markers
                l = l.replacingOccurrences(of: "**", with: "")
                l = l.replacingOccurrences(of: "__", with: "")
                l = l.replacingOccurrences(of: "`", with: "")
                // Single * that is inline emphasis (not list bullet)
                if !l.hasPrefix("* ") && !l.hasPrefix("- ") {
                    l = l.replacingOccurrences(of: "*", with: "")
                }
                return l
            }
            // Collapse multiple consecutive blank lines into one
            .reduce(into: [String]()) { result, line in
                if line.isEmpty && result.last?.isEmpty == true { return }
                result.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cleanup Helpers

    private func detach(_ mountPoint: String) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", mountPoint, "-quiet"]
        try? detach.run()
        detach.waitUntilExit()
    }

    private func cleanup(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

// MARK: - Progress View

private struct UpdateProgressView: View {
    @ObservedObject var manager: UpdateManager

    var body: some View {
        DialogSurface {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppColors.primary)
                Text(manager.progressStatus)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 320, height: 156, alignment: .center)
        }
    }
}

// MARK: - Update Alert View

private struct UpdateAlertView: View {
    let newVersion: String
    let currentVersion: String
    let releaseNotes: String
    let hasDMG: Bool
    let onLater: () -> Void
    let onUpdate: () -> Void

    var body: some View {
        DialogSurface {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Update Available".localized)
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text("v\(currentVersion)").foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        Text("v\(newVersion)").foregroundStyle(AppColors.primary)
                    }
                    .font(.system(size: 12, design: .serif))
                }
                if !releaseNotes.isEmpty {
                    ScrollView(.vertical) {
                        Text(releaseNotes)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Spacer()
                }
                HStack(spacing: 10) {
                    DialogActionButton(title: "Later".localized, action: onLater)
                        .keyboardShortcut(.cancelAction)
                    DialogActionButton(title: (hasDMG ? "Update Now" : "Download").localized,
                                       primary: true, action: onUpdate)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 360, height: 340)
        }
    }
}
