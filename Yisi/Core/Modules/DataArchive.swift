import Foundation
import AppKit

/// Export and import of everything a user owns, as one zip.
///
///     Yisi Export 2026-11-02/
///       manifest.json
///       modules/                providers/, presets/, translators/, as is
///       data/history.sqlite     consistent copies taken through the open databases
///       data/learned-rules.sqlite
///       data/HistoryImages/
///       data/settings.plist     preferences, without API keys or machine state
///
/// Keys stay in Keychain and approvals stay on this Mac: an imported module that sends text
/// or runs code asks again. Imports are staged and applied on the next launch, before any
/// database opens, so nothing is replaced underneath a running Yisi.
enum DataArchive {
    static let format = "yisi-export"
    static let version = 1

    struct Summary {
        let modules: Int
        let hasHistory: Bool
        let exportedAt: String
    }

    // MARK: Export

    static func export(to destination: URL, home: YisiHome = .shared, defaults: UserDefaults = .standard) throws {
        let manager = FileManager.default
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let workspace = home.scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = workspace.appendingPathComponent("Yisi Export \(stamp)", isDirectory: true)
        defer { try? manager.removeItem(at: workspace) }
        let data = folder.appendingPathComponent("data", isDirectory: true)
        try manager.createDirectory(at: data, withIntermediateDirectories: true)

        if manager.fileExists(atPath: home.modules.path) {
            try manager.copyItem(at: home.modules, to: folder.appendingPathComponent("modules", isDirectory: true))
        }
        try DatabaseManager.shared.backup(to: data.appendingPathComponent("history.sqlite"))
        try LearningManager.shared.backup(to: data.appendingPathComponent("learned-rules.sqlite"))
        let images = home.data.appendingPathComponent("HistoryImages", isDirectory: true)
        if manager.fileExists(atPath: images.path) {
            try manager.copyItem(at: images, to: data.appendingPathComponent("HistoryImages", isDirectory: true))
        }
        let settings = try PropertyListSerialization.data(fromPropertyList: preferences(from: defaults), format: .xml, options: 0)
        try settings.write(to: data.appendingPathComponent("settings.plist"))

        let manifest: [String: Any] = [
            "format": format, "version": version, "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "app": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("manifest.json"))

        try? manager.removeItem(at: destination)
        try ditto(["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, destination.path])
    }

    /// Preferences worth carrying to another Mac. API keys, permissions, onboarding and window state stay behind.
    static func preferences(from defaults: UserDefaults) -> [String: Any] {
        let domain = defaults.dictionaryRepresentation()
        let keys = AppDefaults.Keys.self
        let portable: Set<String> = [
            keys.appTheme, keys.popupLiquidGlass, keys.accentColorHex, keys.popupTintHex, keys.popupTintStrength,
            keys.appLanguage, keys.closeMode, keys.autoCheckUpdates, keys.translationEngine,
            keys.defaultSourceLanguage, keys.defaultTargetLanguage, keys.enableImproveFeature, keys.presetModeEnabled,
            keys.selectedPresetId, keys.savedPresets, keys.externalTranslator, keys.apiProvider, keys.imageApiProvider,
            keys.enableDeepThinking, keys.imageProcessingStrategy, keys.applyApiToImageMode,
            keys.globalShortcutKey, keys.globalShortcutModifiers, keys.screenshotShortcutKey, keys.screenshotShortcutModifiers,
            "enable_custom_mode_popup",
        ]
        return domain.filter { key, _ in
            !key.hasSuffix("_api_key") && (portable.contains(key) || key.hasSuffix("_model")
                || key.hasPrefix("model_capabilities.") || key.hasPrefix("custom_service") || key.hasPrefix("image_custom_service"))
        }
    }

    // MARK: Import

    /// Unpacks and checks an archive, then stages it for the next launch.
    static func stageImport(from archive: URL, home: YisiHome = .shared) throws -> Summary {
        let manager = FileManager.default
        let workspace = home.scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: workspace) }
        try manager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try ditto(["-x", "-k", archive.path, workspace.path])

        let candidates = [workspace] + ((try? manager.contentsOfDirectory(at: workspace, includingPropertiesForKeys: nil)) ?? [])
        guard let root = candidates.first(where: { manager.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }),
              let summary = try? summary(of: root) else {
            throw NSError(domain: "YisiData", code: 2, userInfo: [NSLocalizedDescriptionKey: "This file is not a Yisi export.".localized])
        }
        try? manager.removeItem(at: home.pendingImport)
        try manager.moveItem(at: root, to: home.pendingImport)
        return summary
    }

    static func summary(of root: URL) throws -> Summary {
        let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              manifest["format"] as? String == format, (manifest["version"] as? Int ?? .max) <= version else {
            throw NSError(domain: "YisiData", code: 2)
        }
        let modules = ModuleRole.allCases.reduce(0) { count, role in
            let folder = root.appendingPathComponent("modules").appendingPathComponent(role.folder)
            return count + moduleFolders(in: folder).count
        }
        return Summary(modules: modules,
                       hasHistory: FileManager.default.fileExists(atPath: root.appendingPathComponent("data/history.sqlite").path),
                       exportedAt: manifest["exportedAt"] as? String ?? "")
    }

    /// Applies a staged import. Called first thing at launch, before databases open.
    static func applyPendingImport(home: YisiHome = .shared, defaults: UserDefaults = .standard) {
        let manager = FileManager.default
        let pending = home.pendingImport
        guard manager.fileExists(atPath: pending.appendingPathComponent("manifest.json").path) else { return }
        defer { try? manager.removeItem(at: pending) }
        try? manager.createDirectory(at: home.modules, withIntermediateDirectories: true)
        try? manager.createDirectory(at: home.data, withIntermediateDirectories: true)

        for role in ModuleRole.allCases {
            let modules = pending.appendingPathComponent("modules", isDirectory: true).appendingPathComponent(role.folder, isDirectory: true)
            let target = home.modules.appendingPathComponent(role.folder, isDirectory: true)
            try? manager.createDirectory(at: target, withIntermediateDirectories: true)
            for folder in moduleFolders(in: modules) {
                let destination = target.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
                if manager.fileExists(atPath: destination.path) { try? manager.trashItem(at: destination, resultingItemURL: nil) }
                try? manager.moveItem(at: folder, to: destination)
            }
        }

        let data = pending.appendingPathComponent("data", isDirectory: true)
        for (name, target) in [("history.sqlite", home.historyDatabase), ("learned-rules.sqlite", home.learnedRulesDatabase)] {
            let source = data.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path) else { continue }
            for suffix in ["", "-wal", "-shm"] { try? manager.removeItem(atPath: target.path + suffix) }
            try? manager.moveItem(at: source, to: target)
        }
        let images = data.appendingPathComponent("HistoryImages", isDirectory: true)
        if manager.fileExists(atPath: images.path) {
            let target = home.data.appendingPathComponent("HistoryImages", isDirectory: true)
            try? manager.removeItem(at: target)
            try? manager.moveItem(at: images, to: target)
        }
        if let settings = try? Data(contentsOf: data.appendingPathComponent("settings.plist")),
           let values = try? PropertyListSerialization.propertyList(from: settings, format: nil) as? [String: Any] {
            for (key, value) in values where !key.hasSuffix("_api_key") { defaults.set(value, forKey: key) }
        }
    }

    /// The module folders inside a kind's folder; Yisi's own AGENTS.md is not one.
    private static func moduleFolders(in directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "YisiData", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Could not read or write the archive.".localized])
        }
    }
}

enum AppRelauncher {
    /// Opens a new instance after this one quits.
    @MainActor static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; exec /usr/bin/open -n \"$1\"", "yisi-relaunch", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
