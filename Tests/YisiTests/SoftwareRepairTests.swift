import XCTest
@testable import Yisi

final class SoftwareRepairTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var domain: String!

    override func setUpWithError() throws {
        domain = "YisiRepairTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: domain)
        try FileManager.default.removeItem(at: root)
    }

    private func seed() {
        defaults.set("broken-theme", forKey: AppDefaults.Keys.appTheme)
        defaults.set(999, forKey: AppDefaults.Keys.globalShortcutKey)
        defaults.set("fake-test-key", forKey: AppDefaults.Keys.openaiApiKey)
        defaults.set("fake-image-key", forKey: AppDefaults.Keys.imageGeminiApiKey)
        defaults.set(Data("custom-config".utf8), forKey: "custom_service")
        defaults.set("OpenAI", forKey: AppDefaults.Keys.apiProvider)
        defaults.set("user-model", forKey: AppDefaults.Keys.openaiModel)
        defaults.set(Data("user-profiles".utf8), forKey: "model_capabilities.text.OpenAI.user-model")
        defaults.set("presets", forKey: AppDefaults.Keys.savedPresets)
        defaults.set(true, forKey: AppDefaults.Keys.welcomeCompleted)
        defaults.set("future-user-data", forKey: "unknown_future_key")
    }

    func testRepairPreservesAllCredentialsServiceProfilesAndUserData() throws {
        seed()
        let before = try XCTUnwrap(defaults.persistentDomain(forName: domain))
        _ = try SoftwareRepair.perform(defaults: defaults, domain: domain,
            backupRoot: root.appendingPathComponent("Backups"), cacheURLs: [])
        let after = try XCTUnwrap(defaults.persistentDomain(forName: domain))
        let expected = before.filter { !SoftwareRepair.resetKeys.contains($0.key) }
        XCTAssertEqual(after as NSDictionary, expected as NSDictionary)
    }

    func testHistoryImagesAndLearningFilesRemainUnchangedAndCacheCanBeRecovered() throws {
        seed()
        let protectedFiles = ["Documents/YisiHistory.sqlite", "Documents/YisiHistory.sqlite-wal",
            "Documents/YisiHistory.sqlite-shm", "Documents/HistoryImages/shot.png",
            "Library/Application Support/com.yisi.app/learned_rules.db"]
        for name in protectedFiles {
            let path = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(name.utf8).write(to: path)
        }
        let cache = root.appendingPathComponent("Caches/com.sonianmu.yisi")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("old cache".utf8).write(to: cache.appendingPathComponent("entry"))
        let receipt = try SoftwareRepair.perform(defaults: defaults, domain: domain,
            backupRoot: root.appendingPathComponent("Backups"), cacheURLs: [cache])
        for name in protectedFiles { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name)), Data(name.utf8)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(receipt.archivedCaches, 1)
        XCTAssertEqual(try Data(contentsOf: receipt.backupURL.appendingPathComponent("cache-0/entry")), Data("old cache".utf8))
    }

    func testPrivatePreferenceBackupExcludesCredentialsAndCanRestoreRemovedSettings() throws {
        seed()
        let receipt = try SoftwareRepair.perform(defaults: defaults, domain: domain,
            backupRoot: root.appendingPathComponent("Backups"), cacheURLs: [])
        let path = receipt.backupURL.appendingPathComponent("preferences.plist")
        let snapshot = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as? [String: Any])
        XCTAssertEqual(snapshot[AppDefaults.Keys.appTheme] as? String, "broken-theme")
        XCTAssertNil(snapshot[AppDefaults.Keys.openaiApiKey])
        XCTAssertNil(snapshot["custom_service"])
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directory = try FileManager.default.attributesOfItem(atPath: receipt.backupURL.path)
        XCTAssertEqual((directory[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        for (key, value) in snapshot { defaults.set(value, forKey: key) }
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.appTheme), "broken-theme")
    }

    func testBackupFailureLeavesPreferencesUntouched() throws {
        seed()
        let before = try XCTUnwrap(defaults.persistentDomain(forName: domain))
        let occupied = root.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: occupied)
        XCTAssertThrowsError(try SoftwareRepair.perform(defaults: defaults, domain: domain, backupRoot: occupied, cacheURLs: []))
        XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, before as NSDictionary)
    }

    func testCacheFailureRestoresPreviouslyMovedCachesBeforeChangingPreferences() throws {
        seed()
        let before = try XCTUnwrap(defaults.persistentDomain(forName: domain))
        let first = root.appendingPathComponent("first-cache")
        let second = root.appendingPathComponent("second-cache")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let fm = FailingCacheMove()
        fm.failSource = second
        XCTAssertThrowsError(try SoftwareRepair.perform(defaults: defaults, domain: domain,
            backupRoot: root.appendingPathComponent("Backups"), cacheURLs: [first, second], fileManager: fm))
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, before as NSDictionary)
    }
}

private final class FailingCacheMove: FileManager, @unchecked Sendable {
    var failSource: URL?
    override func moveItem(at source: URL, to destination: URL) throws {
        if source == failSource { throw NSError(domain: "RepairTest", code: 1) }
        try super.moveItem(at: source, to: destination)
    }
}
