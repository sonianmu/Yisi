import XCTest
@testable import Yisi

final class AIServiceDraftTests: XCTestCase {
    private var domain: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        domain = "AIServiceDraftTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
    }
    override func tearDown() { defaults.removePersistentDomain(forName: domain) }

    func testNewModelDefaultsAreEmptyAndExistingModelIsPreserved() {
        XCTAssertEqual(AppDefaults.translationEngine, "ai")
        for provider in [APIProvider.openai, .gemini, .zhipu, .minimax, .deepseek] {
            XCTAssertEqual(AIConfigurationStore.presetConnection(provider: provider).model, "")
            XCTAssertEqual(AIServiceDraft.load(image: false, provider: provider, defaults: defaults).model, "")
        }
        defaults.set("old-user-model", forKey: "openai_model")
        XCTAssertEqual(AIServiceDraft.load(image: false, provider: .openai, defaults: defaults).model, "old-user-model")
    }

    @MainActor func testIndependentVisionConfigurationAcceptsEveryBuiltInProvider() async throws {
        for provider in [APIProvider.openai, .gemini, .zhipu, .minimax, .deepseek] {
            var draft = AIServiceDraft.load(image: true, provider: provider, defaults: defaults)
            draft.apiKey = "image-key"
            draft.model = "user-vision-model"
            _ = try await draft.testAndSave(defaults: defaults, send: { messages, config in
                XCTAssertNotNil(messages.first?.content.image)
                _ = try AIHTTPTransport().makeRequest(messages: messages, config: config)
                return "OK"
            })
            defaults.set(false, forKey: AppDefaults.Keys.applyApiToImageMode)
            let service = AIConfigurationStore.resolve(image: true, defaults: defaults)
            XCTAssertEqual(service.provider, provider)
            XCTAssertEqual(service.model, "user-vision-model")
            XCTAssertEqual(service.apiKey, "image-key")
        }
    }

    @MainActor func testDraftDoesNotSaveUntilSuccessfulTestThenActivatesAI() async throws {
        defaults.set("old-model", forKey: "openai_model")
        defaults.set("system", forKey: AppDefaults.Keys.translationEngine)
        var draft = AIServiceDraft.load(image: false, provider: .openai, defaults: defaults)
        draft.apiKey = " new-key "
        draft.model = " future-model "
        XCTAssertEqual(defaults.string(forKey: "openai_model"), "old-model")
        let response = try await draft.testAndSave(defaults: defaults, send: { _, config in
            XCTAssertEqual(config.model, "future-model")
            XCTAssertEqual(config.apiKey, "new-key")
            return "OK"
        })
        XCTAssertEqual(response, "OK")
        XCTAssertEqual(defaults.string(forKey: "openai_model"), "future-model")
        XCTAssertEqual(defaults.string(forKey: "openai_api_key"), "new-key")
        XCTAssertEqual(defaults.string(forKey: "api_provider"), "OpenAI")
        XCTAssertEqual(defaults.string(forKey: AppDefaults.Keys.translationEngine), "ai")
    }

    @MainActor func testFailedRequestDoesNotOverwritePreviousCredentialsOrEngine() async throws {
        defaults.set("old-key", forKey: "openai_api_key")
        defaults.set("old-model", forKey: "openai_model")
        defaults.set("system", forKey: AppDefaults.Keys.translationEngine)
        let before = try XCTUnwrap(defaults.persistentDomain(forName: domain))
        var draft = AIServiceDraft.load(image: false, provider: .openai, defaults: defaults)
        draft.apiKey = "bad-key"
        draft.model = "bad-model"
        do {
            _ = try await draft.testAndSave(defaults: defaults, send: { _, _ in throw AIServiceError.http(401, "invalid key") })
            XCTFail("Expected failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("401")) }
        XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, before as NSDictionary)
    }

    @MainActor func testBlankFieldsNeverSendOrSave() async {
        for (key, model) in [("", "model"), ("key", ""), (" ", " ")] {
            var draft = AIServiceDraft.load(image: false, provider: .openai, defaults: defaults)
            draft.apiKey = key
            draft.model = model
            do {
                _ = try await draft.testAndSave(defaults: defaults, send: { _, _ in XCTFail("Must not send"); return "OK" })
                XCTFail("Expected validation failure")
            } catch {}
            XCTAssertNil(defaults.string(forKey: "openai_model"))
        }
    }

    @MainActor func testVisionDraftTestsImageAndSavesIndependently() async throws {
        defaults.set("text-model", forKey: "openai_model")
        var draft = AIServiceDraft.load(image: true, provider: .gemini, defaults: defaults)
        draft.apiKey = "image-key"
        draft.model = "future-vision-model"
        _ = try await draft.testAndSave(defaults: defaults, send: { messages, config in
            XCTAssertNotNil(messages.first?.content.image)
            XCTAssertTrue(config.capabilities.supportsImages)
            XCTAssertEqual(config.model, "future-vision-model")
            return "OK"
        })
        XCTAssertEqual(defaults.string(forKey: "image_gemini_model"), "future-vision-model")
        XCTAssertEqual(defaults.string(forKey: "openai_model"), "text-model")
    }

    @MainActor func testKeychainFailureLeavesSelectedCustomServiceUnchanged() async throws {
        defaults.set("OpenAI", forKey: "api_provider")
        let before = try XCTUnwrap(defaults.persistentDomain(forName: domain))
        var draft = AIServiceDraft.load(image: false, provider: .custom, defaults: defaults, readCredential: { _ in "" })
        draft.apiKey = "new-key"
        draft.model = "custom-model"
        draft.baseURL = "https://example.test/v1"
        do {
            _ = try await draft.testAndSave(defaults: defaults, send: { _, _ in "OK" }, saveCredential: { _, _ in
                throw NSError(domain: "TestKeychain", code: 1)
            })
            XCTFail("Expected Keychain failure")
        } catch {}
        XCTAssertEqual(defaults.persistentDomain(forName: domain)! as NSDictionary, before as NSDictionary)
    }

    func testUnconfiguredServiceHasActionableErrorWhileHTTPFailureStaysDistinct() {
        let service = ResolvedAIService(provider: .openai, apiProtocol: .chatCompletions,
            baseURL: "https://example.test/v1", apiKey: "", model: "", capabilities: ModelCapabilities())
        XCTAssertThrowsError(try service.requireConfigured()) { error in
            XCTAssertTrue(error.localizedDescription.contains("AI"))
        }
        XCTAssertTrue(AIServiceError.http(503, "upstream unavailable").localizedDescription.contains("503"))
    }
}
