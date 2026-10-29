import XCTest
@testable import Yisi

final class UpdateReleaseTests: XCTestCase {
    private let url = URL(string: "https://api.github.com/repos/sonianmu/Yisi/releases/latest")!
    private let validJSON = Data("""
        {"tag_name":"v1.3.10","html_url":"https://github.com/sonianmu/Yisi/releases/tag/v1.3.10",
         "assets":[{"name":"Yisi.dmg","browser_download_url":"https://github.com/sonianmu/Yisi/releases/download/v1.3.10/Yisi.dmg"}]}
        """.utf8)

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testValidReleaseFindsInstallerAndUsesNumericVersionComparison() throws {
        let release = try UpdateRelease.decode(data: validJSON, response: response(200), error: nil)
        XCTAssertEqual(release.version, "1.3.10")
        XCTAssertEqual(release.dmgURL?.lastPathComponent, "Yisi.dmg")
        XCTAssertTrue(release.isNewer(than: "1.3.4"))
        XCTAssertFalse(release.isNewer(than: "1.3.10"))
        XCTAssertFalse(release.isNewer(than: "1.3.10.0"))
        XCTAssertFalse(release.isNewer(than: "1.4.0"))
    }

    func testHTTPFailuresAreNotClassifiedAsUpToDate() {
        for status in [403, 404, 429, 500] {
            XCTAssertThrowsError(try UpdateRelease.decode(data: validJSON, response: response(status), error: nil))
        }
    }

    func testNetworkFailureAndMissingResponseRejectEvenValidCachedData() {
        XCTAssertThrowsError(try UpdateRelease.decode(data: validJSON, response: response(200), error: URLError(.timedOut)))
        XCTAssertThrowsError(try UpdateRelease.decode(data: validJSON, response: nil, error: nil))
        XCTAssertThrowsError(try UpdateRelease.decode(data: nil, response: response(200), error: nil))
    }

    func testMalformedPayloadAndInvalidVersionsAreFailures() {
        for json in ["{}", "not JSON", "{\"tag_name\":\"vlatest\",\"html_url\":\"https://github.com\"}",
                     "{\"tag_name\":\"v1..3\",\"html_url\":\"https://github.com\"}"] {
            XCTAssertThrowsError(try UpdateRelease.decode(data: Data(json.utf8), response: response(200), error: nil))
        }
    }

    func testReleaseWithoutInstallerStillProvidesManualReleasePage() throws {
        let data = Data("{\"tag_name\":\"v1.3.11\",\"html_url\":\"https://github.com/sonianmu/Yisi/releases/tag/v1.3.11\"}".utf8)
        let release = try UpdateRelease.decode(data: data, response: response(200), error: nil)
        XCTAssertTrue(release.isNewer(than: "1.3.10"))
        XCTAssertNil(release.dmgURL)
    }
}
