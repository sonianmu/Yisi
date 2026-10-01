import Foundation
import AppKit
import SwiftUI

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var progressStatus: String = ""

    private let owner = "MUTRO888"
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

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                // A request already in flight must not show an automatic alert
                // after the user switches automatic updates off. Manual checks remain available.
                guard !silent || UserDefaults.standard.bool(forKey: AppDefaults.Keys.autoCheckUpdates) else { return }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String else {
                    if !silent { self.showUpToDate() }
                    return
                }

                let remote = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                self.latestVersion = remote

                // Find DMG asset URL
                var dmgURL: String?
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.hasSuffix(".dmg"),
                           let url = asset["browser_download_url"] as? String {
                            dmgURL = url
                            break
                        }
                    }
                }

                let releaseNotes = json["body"] as? String ?? ""

                if self.isNewer(remote: remote, local: self.currentVersion) {
                    self.updateAvailable = true
                    let alreadyAlerted = self.alertedVersion == remote
                        && self.alertedForCurrent == self.currentVersion
                    if silent && alreadyAlerted { return }
                    self.alertedVersion = remote
                    self.alertedForCurrent = self.currentVersion
                    self.showUpdateAlert(version: remote, htmlURL: htmlURL, dmgURL: dmgURL, releaseNotes: releaseNotes)
                } else {
                    self.updateAvailable = false
                    if !silent { self.showUpToDate() }
                }
            }
        }.resume()
    }

    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    // MARK: - Alerts

    private func showUpdateAlert(version: String, htmlURL: String, dmgURL: String?, releaseNotes: String) {
        guard updateAlertWindow == nil, progressWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating

        let cleanedNotes = cleanMarkdown(releaseNotes)
        let hasDMG = dmgURL != nil

        let view = NSHostingView(rootView:
            UpdateAlertView(
                newVersion: version,
                currentVersion: currentVersion,
                releaseNotes: cleanedNotes,
                hasDMG: hasDMG,
                onLater: { [weak self] in
                    self?.closeUpdateAlertWindow()
                },
                onUpdate: { [weak self] in
                    self?.closeUpdateAlertWindow()
                    if let dmgURL {
                        self?.downloadAndInstall(dmgURL: dmgURL, htmlURL: htmlURL)
                    } else if let url = URL(string: htmlURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        )
        window.contentView = view
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
        let alert = NSAlert()
        alert.messageText = "You're up to date".localized
        alert.informativeText = String(
            format: "Yisi %@ is the latest version.".localized,
            "v\(currentVersion)"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(fallbackURL: String?) {
        closeProgressWindow()
        let alert = NSAlert()
        alert.messageText = "Update Failed".localized
        alert.informativeText = "Auto update failed. You can download manually from GitHub.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Download".localized)
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn, let fallbackURL,
           let url = URL(string: fallbackURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Progress Window

    private func showProgressWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating

        let view = NSHostingView(rootView: UpdateProgressView(manager: self))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        progressWindow = window
    }

    private func closeProgressWindow() {
        progressWindow?.close()
        progressWindow = nil
    }

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
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 20, height: 20)
            Text(manager.progressStatus)
                .font(.system(size: 12, design: .serif))
                .foregroundColor(.secondary)
        }
        .frame(width: 260, height: 80)
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
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Yisi v\(newVersion) \("Update Available".localized)")
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundColor(.primary)

                Text("\("Current Version".localized): v\(currentVersion)")
                    .font(.system(size: 12, design: .serif))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 16)

            // Release Notes
            if !releaseNotes.isEmpty {
                ScrollView(.vertical) {
                    Text(releaseNotes)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button(action: onLater) {
                    Text("Later".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Button(action: onUpdate) {
                    Text((hasDMG ? "Update Now" : "Download").localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppColors.primary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 320, height: 300)
        .background(ThemeBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
