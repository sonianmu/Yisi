import XCTest
@testable import Yisi

final class UpdateReplacementTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default
    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("YisiUpdateTest-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try fm.removeItem(at: root) }

    private func run(launcherResult: Int, backupExists: Bool = false) throws -> Int32 {
        let app = root.appendingPathComponent("Yisi 'quoted' $(literal).app")
        let staged = root.appendingPathComponent("staged.app")
        let dmg = root.appendingPathComponent("update.dmg")
        for path in [app, staged] { try fm.createDirectory(at: path, withIntermediateDirectories: true) }
        try Data("old".utf8).write(to: app.appendingPathComponent("version"))
        try Data("new".utf8).write(to: staged.appendingPathComponent("version"))
        try Data("dmg".utf8).write(to: dmg)
        if backupExists { try fm.createDirectory(atPath: app.path + ".update-backup", withIntermediateDirectories: true) }
        let launcher = root.appendingPathComponent("launcher")
        try "#!/bin/sh\n[ \"$1\" = '-n' ] || exit 99\nprintf '%s' \"$2\" > \"$(dirname \"$0\")/launched\"\nexit \(launcherResult)\n".write(to: launcher, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = UpdateReplacement.arguments(appPath: app.path, stagingPath: staged.path,
            dmgPath: dmg.path, launcher: launcher.path, delay: "0")
        try process.run(); process.waitUntilExit()
        if process.terminationStatus == 0 {
            XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version")), "new")
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("launched")), app.path)
            XCTAssertFalse(fm.fileExists(atPath: app.path + ".update-backup"))
            XCTAssertFalse(fm.fileExists(atPath: dmg.path))
        } else {
            XCTAssertEqual(try String(contentsOf: app.appendingPathComponent("version")), "old")
            XCTAssertTrue(fm.fileExists(atPath: dmg.path))
        }
        return process.terminationStatus
    }

    func testSuccessfulUpdateLaunchesExactPathWithLiteralQuotesAndSpaces() throws {
        XCTAssertEqual(try run(launcherResult: 0), 0)
    }
    func testLaunchFailureRestoresOldApplication() throws {
        XCTAssertEqual(try run(launcherResult: 1), 1)
    }
    func testExistingBackupStopsBeforeOverwritingEitherApplication() throws {
        XCTAssertEqual(try run(launcherResult: 0, backupExists: true), 1)
    }
}
