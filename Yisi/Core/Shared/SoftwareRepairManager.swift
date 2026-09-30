import AppKit
import Combine
import ScreenCaptureKit

@MainActor
final class SoftwareRepairManager: ObservableObject {
    static let shared = SoftwareRepairManager()
    static let issuesURL = URL(string: "https://github.com/MUTRO888/Yisi/issues")!
    @Published private(set) var isRepairing = false

    func presentRepair() {
        guard !isRepairing else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Repair Software".localized
        alert.informativeText = "Repair restores appearance, shortcuts and window layout, archives caches, and attempts to recover unavailable permissions. API keys, service settings, translation history, history images, presets and learned rules are preserved. Settings are backed up first, but some temporary data or personal preferences may be lost. Yisi will restart. If it still does not work, please report the problem on GitHub Issues.".localized
        alert.addButton(withTitle: "Repair and Restart".localized)
        alert.addButton(withTitle: "Cancel".localized)
        // Cancel is the default to avoid triggering a reset with an accidental Return.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runRepair()
    }

    private func runRepair() {
        guard let domain = Bundle.main.bundleIdentifier, Bundle.main.bundleURL.pathExtension == "app" else {
            showFailure("Repair requires launching the installed Yisi app.".localized)
            return
        }
        isRepairing = true
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let backupRoot = support.appendingPathComponent("com.sonianmu.yisi/RepairBackups", isDirectory: true)
        let domains = [domain, "com.yisi.app", "Yisi"]
        let cacheURLs = Set(domains).flatMap { name in
            ["Caches", "HTTPStorages"].map { library.appendingPathComponent("\($0)/\(name)", isDirectory: true) }
        }
        let needsAccessibility = !AXIsProcessTrusted()
        let needsScreenCapture = !CGPreflightScreenCaptureAccess()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let receipt = try SoftwareRepair.perform(defaults: .standard, domain: domain,
                    backupRoot: backupRoot, cacheURLs: cacheURLs)
                var warnings: [String] = []
                for service in [needsAccessibility ? "Accessibility" : nil,
                                needsScreenCapture ? "ScreenCapture" : nil].compactMap({ $0 }) {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                    task.arguments = ["reset", service, domain]
                    // Do not block on pipe buffers or collect unrelated user data.
                    task.standardOutput = FileHandle.nullDevice
                    task.standardError = FileHandle.nullDevice
                    do {
                        try task.run()
                        let deadline = Date().addingTimeInterval(10)
                        while task.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                        if task.isRunning {
                            task.terminate()
                            warnings.append(service)
                        } else if task.terminationStatus != 0 {
                            warnings.append(service)
                        }
                    } catch { warnings.append(service) }
                }
                DispatchQueue.main.async {
                    self.finishRepair(receipt: receipt, needsAuthorization: needsAccessibility || needsScreenCapture,
                                      permissionWarnings: warnings)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRepairing = false
                    self.showFailure(error.localizedDescription)
                }
            }
        }
    }

    private func finishRepair(receipt: SoftwareRepair.Receipt, needsAuthorization: Bool, permissionWarnings: [String]) {
        // Keep the backup path for recovery without storing any credential copies.
        UserDefaults.standard.set(receipt.backupURL.path, forKey: AppDefaults.Keys.repairBackupPath)
        UserDefaults.standard.set(true, forKey: AppDefaults.Keys.repairPending)
        if needsAuthorization {
            UserDefaults.standard.set(2, forKey: AppDefaults.Keys.welcomeStep)
        }
        guard UserDefaults.standard.synchronize() else {
            isRepairing = false
            showFailure("Could not save the restart state. The backup has been retained.".localized)
            return
        }
        if !permissionWarnings.isEmpty {
            let alert = NSAlert()
            alert.messageText = "System authorization still required".localized
            alert.informativeText = "Settings and caches have been repaired. Some permissions could not be reset automatically; after restart, follow the authorization prompts. If the problem persists, please report it on GitHub Issues.".localized
            alert.addButton(withTitle: "Restart".localized)
            alert.addButton(withTitle: "GitHub Issues".localized)
            if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(Self.issuesURL) }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        var arguments = ["-c", "sleep 1; exec /usr/bin/open -n \"$@\"", "yisi-repair", Bundle.main.bundlePath]
        if ProcessInfo.processInfo.arguments.contains("-auto_check_updates") {
            arguments += ["--args", "-auto_check_updates", "NO"]
        }
        task.arguments = arguments
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            isRepairing = false
            showFailure(error.localizedDescription)
        }
    }

    private func showFailure(_ reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Repair could not finish".localized
        alert.informativeText = "Your API keys and history have not been deleted. Please report the problem on GitHub Issues if it persists.".localized + "\n\n" + reason
        alert.addButton(withTitle: "OK".localized)
        alert.addButton(withTitle: "GitHub Issues".localized)
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(Self.issuesURL) }
    }
}
