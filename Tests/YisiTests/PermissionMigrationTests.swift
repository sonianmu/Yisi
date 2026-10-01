import XCTest
@testable import Yisi

final class PermissionMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let old = PermissionMigration.Identity(version: "1.2.1", requirement: "cdhash OLD")
    private let new = PermissionMigration.Identity(version: "1.3.0", requirement: "cdhash NEW")

    override func setUp() {
        suite = "YisiPermissionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func seed(_ identity: PermissionMigration.Identity) throws {
        try PermissionMigration.checkpoint(.init(identity: identity, services: []), defaults: defaults, persist: { true })
    }
    private func plan(_ identity: PermissionMigration.Identity, existing: Bool = true,
                      ax: Bool = true, screen: Bool = true) -> PermissionMigration.Plan {
        PermissionMigration.plan(identity: identity, existingUser: existing,
                                 accessibility: ax, screenCapture: screen, defaults: defaults)
    }

    func testFreshInstallDoesNotResetDeniedPermissions() throws {
        let value = plan(new, existing: false, ax: false, screen: false)
        XCTAssertTrue(value.services.isEmpty)
        try PermissionMigration.checkpoint(value, defaults: defaults, persist: { true })
        XCTAssertFalse(defaults.bool(forKey: PermissionMigration.pendingKey))
    }

    func testLegacyUpgradeRefreshesDeniedEntriesOnce() throws {
        let value = plan(new, ax: false, screen: false)
        XCTAssertEqual(value.services, ["Accessibility", "ScreenCapture"])
        try PermissionMigration.checkpoint(value, defaults: defaults, persist: { true })
        XCTAssertEqual(defaults.integer(forKey: AppDefaults.Keys.welcomeStep), 2)
        XCTAssertTrue(defaults.bool(forKey: PermissionMigration.pendingKey))
        XCTAssertTrue(plan(new).services.isEmpty)
    }

    func testLegacyUserNewlyGrantedAccessibilityIsNeverCleared() throws {
        let value = plan(new, ax: true, screen: false)
        XCTAssertEqual(value.services, ["ScreenCapture"])
        try PermissionMigration.checkpoint(value, defaults: defaults, persist: { true })
        XCTAssertTrue(plan(new, ax: true, screen: false).services.isEmpty)
    }

    func testSignatureChangePreservesAlreadyGrantedPermissions() throws {
        try seed(old)
        XCTAssertTrue(plan(new).services.isEmpty)
        XCTAssertEqual(plan(new, screen: false).services, ["ScreenCapture"])
    }

    func testSameVersionRebuildDetectsNewSignature() throws {
        try seed(new)
        let rebuilt = PermissionMigration.Identity(version: "1.3.0", requirement: "cdhash REBUILD")
        XCTAssertTrue(plan(rebuilt).services.isEmpty)
        XCTAssertEqual(plan(rebuilt, ax: false, screen: false).services.count, 2)
    }

    func testStableSignatureUpgradeKeepsValidGrantsAndOnlyResetsMissingOnes() throws {
        let stable = "identifier com.sonianmu.yisi and anchor trusted"
        try seed(.init(version: "1.2.1", requirement: stable))
        let update = PermissionMigration.Identity(version: "1.3.0", requirement: stable)
        XCTAssertTrue(plan(update).services.isEmpty)
        XCTAssertEqual(plan(update, screen: false).services, ["ScreenCapture"])
    }

    func testFailureAndCrashCheckpointNeverCauseRestartLoop() throws {
        let value = plan(new, ax: false, screen: false)
        try PermissionMigration.checkpoint(value, defaults: defaults, persist: { true })
        XCTAssertTrue(plan(new, ax: false, screen: false).services.isEmpty)
        PermissionMigration.finish(value, failures: value.services, defaults: defaults)
        try PermissionMigration.checkpoint(plan(new), defaults: defaults, persist: { true })
        XCTAssertEqual(PermissionMigration.state(defaults: defaults)?.failedServices, value.services)
        XCTAssertTrue(defaults.bool(forKey: PermissionMigration.pendingKey))
    }

    func testCheckpointFailureRestoresStateBeforeAnyReset() throws {
        try seed(old)
        defaults.set(1, forKey: AppDefaults.Keys.welcomeStep)
        XCTAssertThrowsError(try PermissionMigration.checkpoint(plan(new, ax: false, screen: false), defaults: defaults, persist: { false }))
        XCTAssertEqual(PermissionMigration.state(defaults: defaults)?.identity, old)
        XCTAssertEqual(defaults.integer(forKey: AppDefaults.Keys.welcomeStep), 1)
        XCTAssertNil(defaults.object(forKey: PermissionMigration.pendingKey))
    }

    func testMigrationKeepsCredentialsConfigurationAndHistoryPreferences() throws {
        let protected: [String: Any] = ["openai_api_key": "secret", "openai_model": "user-model",
            "custom_ai_service": "config", "saved_presets": "presets", "translation_engine": "system",
            "history_path": "/Users/example/history.sqlite", "unknown_preference": 42]
        protected.forEach { defaults.set($0.value, forKey: $0.key) }
        let migration = plan(new, ax: false, screen: false)
        try PermissionMigration.checkpoint(migration, defaults: defaults, persist: { true })
        PermissionMigration.finish(migration, failures: [], defaults: defaults)
        PermissionMigration.completeAuthorization(defaults: defaults)
        for (key, value) in protected {
            XCTAssertEqual(defaults.object(forKey: key) as? NSObject, value as? NSObject)
        }
        XCTAssertFalse(defaults.bool(forKey: PermissionMigration.pendingKey))
    }

    func testResetIsScopedAndRegistersExactApplicationBeforeResetting() {
        var calls: [(String, [String])] = []
        let failures = PermissionReset.perform(services: ["Accessibility", "ScreenCapture"],
            bundleID: "com.sonianmu.yisi", appPath: "/Applications/My Folder/Yisi.app") { executable, args in
                calls.append((executable, args))
                return args != ["reset", "ScreenCapture", "com.sonianmu.yisi"]
            }
        XCTAssertEqual(calls.first?.1, ["-f", "/Applications/My Folder/Yisi.app"])
        XCTAssertEqual(calls.dropFirst().map(\.1), [["reset", "Accessibility", "com.sonianmu.yisi"], ["reset", "ScreenCapture", "com.sonianmu.yisi"]])
        XCTAssertEqual(failures, ["ScreenCapture"])
    }

    func testRegistrationFailureAndInvalidScopeNeverResetOtherApps() {
        var resets = 0
        let result = PermissionReset.perform(services: ["Accessibility"], bundleID: "com.sonianmu.yisi", appPath: "/Applications/Yisi.app") { _, _ in false }
        XCTAssertEqual(result, ["Accessibility"])
        _ = PermissionReset.perform(services: ["All"], bundleID: "other.app", appPath: "/Applications/Yisi.app") { _, _ in resets += 1; return true }
        XCTAssertEqual(resets, 0)
    }

    func testGrantBecomingAvailableDuringRegistrationIsNotReset() {
        var resets: [[String]] = []
        let failures = PermissionReset.perform(services: ["Accessibility", "ScreenCapture"],
            bundleID: "com.sonianmu.yisi", appPath: "/Applications/Yisi.app",
            isGranted: { $0 == "Accessibility" }) { _, arguments in
                if arguments.first == "reset" { resets.append(arguments) }
                return true
            }
        XCTAssertTrue(failures.isEmpty)
        XCTAssertEqual(resets, [["reset", "ScreenCapture", "com.sonianmu.yisi"]])
    }
}
