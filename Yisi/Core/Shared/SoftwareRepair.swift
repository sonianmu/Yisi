import Foundation

/// A deliberately narrow reset: protected data is never deleted or rewritten.
enum SoftwareRepair {
    static let resetKeys = [
        AppDefaults.Keys.appTheme, AppDefaults.Keys.closeMode,
        AppDefaults.Keys.globalShortcutKey, AppDefaults.Keys.globalShortcutModifiers,
        AppDefaults.Keys.screenshotShortcutKey, AppDefaults.Keys.screenshotShortcutModifiers,
        AppDefaults.Keys.popupFrameRect
    ]

    struct Receipt {
        let backupURL: URL
        let archivedCaches: Int
    }

    static func perform(defaults: UserDefaults, domain: String, backupRoot: URL,
                        cacheURLs: [URL], fileManager: FileManager = .default) throws -> Receipt {
        let persisted = defaults.persistentDomain(forName: domain) ?? [:]
        let snapshot = persisted.filter { resetKeys.contains($0.key) }
        let backup = backupRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        // The backup contains only resettable preferences, never API credentials.
        let data = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        let preferencesURL = backup.appendingPathComponent("preferences.plist")
        try data.write(to: preferencesURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: preferencesURL.path)

        var moved: [(source: URL, destination: URL)] = []
        do {
            for (index, source) in cacheURLs.enumerated() where fileManager.fileExists(atPath: source.path) {
                let destination = backup.appendingPathComponent("cache-\(index)")
                try fileManager.moveItem(at: source, to: destination)
                moved.append((source, destination))
            }
        } catch {
            // Preference changes happen only after every cache was safely archived.
            for pair in moved.reversed() {
                try? fileManager.moveItem(at: pair.destination, to: pair.source)
            }
            throw error
        }

        for key in resetKeys { defaults.removeObject(forKey: key) }
        guard defaults.synchronize() else {
            for (key, value) in snapshot { defaults.set(value, forKey: key) }
            for pair in moved.reversed() { try? fileManager.moveItem(at: pair.destination, to: pair.source) }
            throw NSError(domain: "YisiRepair", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not save repaired settings. The backup has been retained.".localized
            ])
        }
        return Receipt(backupURL: backup, archivedCaches: moved.count)
    }
}
