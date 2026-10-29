import XCTest
@testable import Yisi

final class PermissionRequestTests: XCTestCase {
    func testExistingGrantDoesNotRegisterOrRequest() {
        let outcome = PermissionRequest.perform(preflight: { true }, registerApplication: {
            XCTFail("Already authorized"); return false
        }, requestAccess: {
            XCTFail("Must not request again"); return false
        })
        XCTAssertEqual(outcome, .granted)
    }

    func testApplicationRegistrationIsFollowedOnlyByNativeRequest() {
        var calls: [String] = []
        let outcome = PermissionRequest.perform(preflight: { false }, registerApplication: {
            calls.append("register"); return true
        }, requestAccess: {
            calls.append("native-request"); return false
        })
        XCTAssertEqual(outcome, .awaitingUser)
        XCTAssertEqual(calls, ["register", "native-request"])
    }

    func testRegistrationFailureDoesNotRequestAuthorization() {
        let outcome = PermissionRequest.perform(preflight: { false }, registerApplication: { false }, requestAccess: {
            XCTFail("Registration failed"); return false
        })
        XCTAssertEqual(outcome, .registrationFailed)
    }

    func testImmediateGrantFinishesRequest() {
        let outcome = PermissionRequest.perform(preflight: { false }, registerApplication: { true },
            requestAccess: { true })
        XCTAssertEqual(outcome, .granted)
    }

    func testGrantSettlingDuringRequestIsRechecked() {
        var granted = false
        let outcome = PermissionRequest.perform(preflight: { granted }, registerApplication: { true }, requestAccess: {
            granted = true
            return false
        })
        XCTAssertEqual(outcome, .granted)
    }

    func testRegistrationUsesCurrentBundlePathAndRejectsOtherApplications() {
        var calls: [[String]] = []
        XCTAssertTrue(PermissionReset.registerApplication(bundleID: "com.sonianmu.yisi", appPath: "/Applications/Yisi.app") { _, arguments in
            calls.append(arguments)
            return true
        })
        XCTAssertEqual(calls, [["-f", "/Applications/Yisi.app"]])
        XCTAssertFalse(PermissionReset.registerApplication(bundleID: "other.app", appPath: "/Applications/Yisi.app") { _, _ in
            XCTFail("Unrelated bundle must not be registered")
            return true
        })
    }
}
