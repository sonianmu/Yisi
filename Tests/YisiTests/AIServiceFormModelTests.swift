import XCTest
@testable import Yisi

@MainActor final class AIServiceFormModelTests: XCTestCase {
    private func isolatedDefaults() throws -> (String, UserDefaults) {
        let domain = "AIServiceFormModelTests.\(UUID().uuidString)"
        return (domain, try XCTUnwrap(UserDefaults(suiteName: domain)))
    }

    func testWelcomeNextSavesAndSettingsReloadsEveryProvider() async throws {
        let (domain, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        for provider in [APIProvider.openai, .gemini, .zhipu, .minimax, .deepseek, .custom] {
            var credential = ""
            var draft = AIServiceDraft.load(image: false, provider: provider, defaults: defaults, readCredential: { _ in "" })
            draft.apiKey = "welcome-key"
            draft.model = "welcome-model"
            if provider == .custom { draft.baseURL = "https://example.test/v1" }
            let form = AIServiceFormModel(draft: draft, save: { submitted in
                try await submitted.testAndSave(defaults: defaults, send: { _, _ in "OK" }, saveCredential: { data, _ in
                    credential = String(decoding: data, as: UTF8.self)
                })
            })
            let mayContinue = await form.testAndSave(reuseSaved: true)
            XCTAssertTrue(mayContinue)
            // A new defaults instance and form represent the settings page after relaunch.
            let reloaded = AIServiceDraft.load(image: false, defaults: try XCTUnwrap(UserDefaults(suiteName: domain)), readCredential: { _ in credential })
            XCTAssertEqual(reloaded.provider, provider)
            XCTAssertEqual(reloaded.apiKey, "welcome-key")
            XCTAssertEqual(reloaded.model, "welcome-model")
        }
    }

    func testNextReusesSuccessfulSaveButTestsAgainAfterEditing() async throws {
        let (domain, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        var requests = 0
        let form = AIServiceFormModel(draft: AIServiceDraft.load(image: false, defaults: defaults), save: { _ in
            requests += 1
            return "OK"
        })
        let first = await form.testAndSave()
        let next = await form.testAndSave(reuseSaved: true)
        XCTAssertTrue(first && next)
        XCTAssertEqual(requests, 1)
        form.draft.apiKey = "edited-key"
        let edited = await form.testAndSave(reuseSaved: true)
        XCTAssertTrue(edited)
        XCTAssertEqual(requests, 2)
    }

    func testFailedNextKeepsInputAndPreviouslySavedCredentials() async throws {
        let (domain, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("old-key", forKey: "openai_api_key")
        defaults.set("old-model", forKey: "openai_model")
        var draft = AIServiceDraft.load(image: false, provider: .openai, defaults: defaults)
        draft.apiKey = "new-key"
        draft.model = "new-model"
        let form = AIServiceFormModel(draft: draft, save: { submitted in
            try await submitted.testAndSave(defaults: defaults, send: { _, _ in throw AIServiceError.http(401, "invalid") })
        })
        let mayContinue = await form.testAndSave(reuseSaved: true)
        XCTAssertFalse(mayContinue)
        XCTAssertEqual(form.draft, draft)
        XCTAssertFalse(form.testing)
        XCTAssertFalse(form.status.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "openai_api_key"), "old-key")
    }

    func testCannotAdvanceWhileSaveIsPending() async throws {
        let (domain, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        var resumeRequest: CheckedContinuation<String, Never>?
        let form = AIServiceFormModel(draft: AIServiceDraft.load(image: false, defaults: defaults), save: { _ in
            await withCheckedContinuation { resumeRequest = $0 }
        })
        let pending = Task { await form.testAndSave() }
        while resumeRequest == nil { await Task.yield() }
        XCTAssertTrue(form.testing)
        let secondNext = await form.testAndSave(reuseSaved: true)
        XCTAssertFalse(secondNext)
        resumeRequest?.resume(returning: "OK")
        let completed = await pending.value
        XCTAssertTrue(completed)
        XCTAssertFalse(form.testing)
    }

    func testCancellationDoesNotSaveOrAdvance() async throws {
        let (domain, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        var draft = AIServiceDraft.load(image: false, provider: .openai, defaults: defaults)
        draft.apiKey = "key"
        draft.model = "model"
        let form = AIServiceFormModel(draft: draft, save: { submitted in
            try await submitted.testAndSave(defaults: defaults, send: { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return "OK"
            })
        })
        let task = Task { await form.testAndSave(reuseSaved: true) }
        let mayContinue = await task.value
        XCTAssertFalse(mayContinue)
        XCTAssertNil(defaults.string(forKey: "openai_api_key"))
    }
}
