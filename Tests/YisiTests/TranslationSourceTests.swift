import XCTest
@testable import Yisi

final class TranslationSourceTests: XCTestCase {
    private func configuration(_ overrides: [String: Any] = [:]) throws -> TranslationSource {
        var values: [String: Any] = [
            "schemaVersion": 1, "id": "test-source", "name": "Test Source",
            "endpoint": "https://example.invalid/translate", "method": "POST", "encoding": "json",
            "headers": [:], "parameters": ["q": "{{text}}", "from": "{{source}}", "to": "{{target}}"],
            "responsePath": ["translations", "*", "text"], "languageMap": ["zh-Hans": "zh"], "requiresSecret": false
        ]
        values.merge(overrides) { _, new in new }
        return try JSONDecoder().decode(TranslationSource.self, from: JSONSerialization.data(withJSONObject: values))
    }

    func testJSONTemplatesEscapeUserTextAndDoNotRecursivelyInterpretIt() throws {
        let source = try configuration()
        try source.validate()
        let text = "译文\n\"} {{secret}} + & 🙂"
        let request = try source.makeRequest(text: text, source: "auto", target: "zh-Hans", secret: "private")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body["q"], text)
        XCTAssertEqual(body["to"], "zh")
        XCTAssertEqual(body["from"], "auto")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testNestedTemplatesAndResponsePaths() throws {
        let source = try configuration(["parameters": ["contents": [["text": "{{text}}"]]]])
        let request = try source.makeRequest(text: "hello", source: "en", target: "zh-Hans", secret: nil)
        let body = try JSONDecoder().decode(SourceJSON.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body, .object(["contents": .array([.object(["text": .string("hello")])])]))
        XCTAssertEqual(try source.translatedText(from: Data(#"{"translations":[{"text":"你好"},{"text":"世界"}]}"#.utf8)), "你好\n世界")
        let arraySource = try configuration(["responsePath": ["0", "*", "0"]])
        XCTAssertEqual(try arraySource.translatedText(from: Data(#"[[["你好","hello"],["世界","world"]]]"#.utf8)), "你好\n世界")
    }

    func testQueryAndFormEncodeReservedCharacters() throws {
        let query = try configuration(["method": "GET", "encoding": "query", "endpoint": "https://example.invalid/?fixed=yes"])
        let request = try query.makeRequest(text: "a+b &你好", source: "en", target: "zh-Hans", secret: nil)
        XCTAssertNil(request.httpBody)
        XCTAssertTrue(request.url!.absoluteString.contains("%2B"))
        let items = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first(where: { $0.name == "q" })?.value, "a+b &你好")
        XCTAssertEqual(items.first(where: { $0.name == "fixed" })?.value, "yes")
        let form = try configuration(["encoding": "form"])
        let formRequest = try form.makeRequest(text: "+ &", source: "en", target: "fr", secret: nil)
        let body = try XCTUnwrap(String(data: XCTUnwrap(formRequest.httpBody), encoding: .utf8))
        XCTAssertTrue(body.contains("%2B"))
        XCTAssertTrue(body.contains("%26"))
        XCTAssertFalse(body.contains("+"))
    }

    func testRequiresSecretAndRejectsHeaderInjectionAfterRendering() throws {
        let source = try configuration(["requiresSecret": true, "headers": ["Authorization": "Bearer {{secret}}"]])
        try source.validate()
        XCTAssertThrowsError(try source.makeRequest(text: "Hello", source: "en", target: "fr", secret: nil))
        XCTAssertThrowsError(try source.makeRequest(text: "Hello", source: "en", target: "fr", secret: "key\r\nX-Foo: bad"))
        let request = try source.makeRequest(text: "Hello", source: "en", target: "fr", secret: "example-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer example-token")
        XCTAssertFalse(request.url!.absoluteString.contains("example-token"))
    }

    func testRejectsInsecureOrExecutableDestinations() throws {
        for endpoint in ["http://example.com", "file:///tmp/secret", "https://user:pass@example.com", "https://example.com/#fragment", "https://{{target}}.example.com", "http://127.0.0.1.evil.test"] {
            XCTAssertThrowsError(try configuration(["endpoint": endpoint]).validate(), endpoint)
        }
        for endpoint in ["https://example.com/translate", "http://127.0.0.1:19387/translate", "http://localhost:19387", "http://[::1]:19387"] {
            XCTAssertNoThrow(try configuration(["endpoint": endpoint]).validate(), endpoint)
        }
    }

    func testRejectsInvalidSchemasMethodsReservedHeadersAndUnknownVariables() throws {
        for overrides: [String: Any] in [
            ["schemaVersion": 2], ["id": "../../bad"], ["name": ""], ["method": "DELETE"],
            ["method": "GET"], ["encoding": "query"], ["responsePath": []],
            ["headers": ["Host": "elsewhere"]], ["headers": ["X-Test": "a\nb"]],
            ["parameters": ["text": "{{unknown}}"]], ["encoding": "form", "parameters": ["q": ["text": "nested"]]]
        ] {
            XCTAssertThrowsError(try configuration(overrides).validate())
        }
    }

    func testRejectsMissingEmptyMalformedAndOversizedResponses() throws {
        let source = try configuration()
        for response in ["not JSON", "{}", #"{"translations":[{"text":" "}]}"#, #"{"translations":[{"text":4}]}"#] {
            XCTAssertThrowsError(try source.translatedText(from: Data(response.utf8)))
        }
        XCTAssertThrowsError(try source.translatedText(from: Data(repeating: 32, count: 2_097_153)))
    }

    @MainActor
    func testStoreRequiresApprovalAndInvalidatesItWhenAgentChangesConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "YisiTests.Sources.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = TranslationSourceStore(directory: directory, defaults: defaults)
        let source = try configuration()
        try store.install(source)
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertFalse(store.isApproved(source))
        defaults.set(source.id, forKey: TranslationSourceStore.selectedKey)
        do {
            _ = try await store.translate("Never send me", source: "en", target: "fr")
            XCTFail("Unapproved source must not send text")
        } catch { XCTAssertTrue(error is TranslationSourceError) }
        store.approve(source)
        XCTAssertTrue(store.isApproved(source))
        let changed = try configuration(["endpoint": "https://other.invalid/translate"])
        try JSONEncoder().encode(changed).write(to: directory.appendingPathComponent(source.id + ".json"))
        store.reload()
        XCTAssertFalse(store.isApproved(try XCTUnwrap(store.sources.first)))
        do {
            _ = try await store.translate("Never send me", source: "en", target: "fr")
            XCTFail("Changed source must not send text")
        } catch { XCTAssertTrue(error is TranslationSourceError) }
        store.approve(changed)
        store.revoke(changed)
        XCTAssertFalse(store.isApproved(changed))
    }

    @MainActor
    func testStoreRejectsInvalidFilesWithoutDiscardingValidSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "YisiTests.Sources.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = TranslationSourceStore(directory: directory, defaults: defaults)
        try store.install(configuration())
        try Data("bad json".utf8).write(to: directory.appendingPathComponent("bad.json"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("linked.json"),
                                                   withDestinationURL: directory.appendingPathComponent("test-source.json"))
        store.reload()
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.loadErrors.count, 2)
    }

    func testNetworkSuccessAndHTTPFailureWithoutLeakingResponseBody() async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [SourceTestURLProtocol.self]
        let source = try configuration()
        let translated = try await TranslationSourceClient.translate("Hello", source: "en", target: "zh-Hans",
                                                                     configuration: source, secret: nil, sessionConfiguration: settings)
        XCTAssertEqual(translated, "你好")
        let failure = try configuration(["endpoint": "https://example.invalid/failure"])
        do {
            _ = try await TranslationSourceClient.translate("Hello", source: "en", target: "fr",
                                                            configuration: failure, secret: nil, sessionConfiguration: settings)
            XCTFail("HTTP failure must throw")
        } catch TranslationSourceError.http(let status) { XCTAssertEqual(status, 403) }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testNetworkTimeoutAndDisconnectionHaveActionableErrors() async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [SourceTestURLProtocol.self]
        for path in ["offline", "timeout"] {
            do {
                let source = try configuration(["endpoint": "https://example.invalid/" + path])
                _ = try await TranslationSourceClient.translate("Hello", source: "en", target: "fr",
                                                                configuration: source, secret: nil, sessionConfiguration: settings)
                XCTFail("Network failure must throw")
            } catch TranslationSourceError.unavailable { XCTAssertEqual(path, "offline") }
            catch TranslationSourceError.timeout { XCTAssertEqual(path, "timeout") }
            catch { XCTFail("Unexpected error: \(error)") }
        }
    }
}

private final class SourceTestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if ["/offline", "/timeout"].contains(request.url?.path) {
            client?.urlProtocol(self, didFailWithError: URLError(request.url?.path == "/timeout" ? .timedOut : .cannotConnectToHost))
            return
        }
        let status = request.url?.path == "/failure" ? 403 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"translations":[{"text":"你好"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
