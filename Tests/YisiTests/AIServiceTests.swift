import XCTest
import AppKit
@testable import Yisi

final class AIServiceTests: XCTestCase {
    private let transport = AIHTTPTransport()

    private func config(_ apiProtocol: AIProtocol = .chatCompletions, caps: ModelCapabilities = ModelCapabilities(),
                        enabled: Bool = false, baseURL: String = "https://example.com/v1", maxTokens: Int = 2048) -> AIRequestConfig {
        AIRequestConfig(apiKey: "test-key", model: "future-model", temperature: 0.3, maxTokens: maxTokens,
                        enableNativeReasoning: enabled, apiProtocol: apiProtocol, baseURL: baseURL, capabilities: caps)
    }

    private func body(_ config: AIRequestConfig, image: Data? = nil) throws -> [String: Any] {
        let request = try transport.makeRequest(messages: [AIMessage(role: .system, text: "Return JSON."),
            AIMessage(role: .user, text: "test", image: image)], config: config)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testBasePathsAndFullEndpoints() throws {
        XCTAssertEqual(try transport.endpoint(baseURL: "https://example.com/api/v1/", apiProtocol: .chatCompletions, model: "x").absoluteString,
                       "https://example.com/api/v1/chat/completions")
        XCTAssertEqual(try transport.endpoint(baseURL: "https://example.com/v1/chat/completions", apiProtocol: .chatCompletions, model: "x").path,
                       "/v1/chat/completions")
        XCTAssertEqual(try transport.endpoint(baseURL: "http://localhost:11434/v1", apiProtocol: .chatCompletions, model: "x").host, "localhost")
        XCTAssertEqual(try transport.endpoint(baseURL: "https://example.com/anthropic/v1", apiProtocol: .anthropic, model: "x").path, "/anthropic/v1/messages")
    }

    func testInvalidURLsRejectedBeforeSending() {
        for url in ["", "example.com", "file:///tmp/x", "https://user:pass@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/v1#x"] {
            XCTAssertThrowsError(try transport.endpoint(baseURL: url, apiProtocol: .chatCompletions, model: "x"), url)
        }
    }

    func testGeminiModelIsEncodedAndKeyStaysOutOfURL() throws {
        let request = try transport.makeRequest(messages: [AIMessage(role: .user, text: "hi")],
            config: config(.gemini, baseURL: "https://example.com/v1beta"))
        XCTAssertEqual(request.url?.path, "/v1beta/models/future-model:generateContent")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
        let url = try transport.endpoint(baseURL: "https://example.com/v1beta", apiProtocol: .gemini, model: "models/x/y?key=bad")
        XCTAssertNil(url.query)
        XCTAssertTrue(url.absoluteString.contains("x%2Fy%3Fkey=bad"))
    }

    func testUnknownCapabilitiesDoNotInventParameters() throws {
        let result = try body(config(enabled: true))
        XCTAssertNil(result["temperature"])
        XCTAssertNil(result["response_format"])
        XCTAssertNil(result["reasoning_effort"])
        XCTAssertNil(result["thinking"])
        XCTAssertEqual(result["model"] as? String, "future-model")
    }

    func testEffortAndTokenParameterAreIndependentOfModelName() throws {
        var caps = ModelCapabilities()
        caps.reasoning = .effort; caps.tokenLimitField = .maxCompletionTokens
        caps.onValue = "high"; caps.offValue = "none"
        for enabled in [false, true] {
            let result = try body(config(caps: caps, enabled: enabled))
            XCTAssertEqual(result["reasoning_effort"] as? String, enabled ? "high" : "none")
            XCTAssertNotNil(result["max_completion_tokens"])
            XCTAssertNil(result["max_tokens"])
        }
    }

    func testToggleAdaptersSendExplicitOff() throws {
        for control in [ReasoningControl.thinkingType, .enableThinking] {
            var caps = ModelCapabilities(); caps.reasoning = control
            for enabled in [false, true] {
                let result = try body(config(caps: caps, enabled: enabled))
                if control == .thinkingType {
                    XCTAssertEqual((result["thinking"] as? [String: String])?["type"], enabled ? "enabled" : "disabled")
                } else { XCTAssertEqual(result["enable_thinking"] as? Bool, enabled) }
            }
        }
    }

    func testGeminiBudgetKeepsRoomForAnswerAndProUsesMinimum() throws {
        var caps = AIConfigurationStore.presetCapabilities(provider: .gemini, model: "gemini-2.5-pro")
        caps.outputTokenLimit = 12000
        for enabled in [false, true] {
            let result = try body(config(.gemini, caps: caps, enabled: enabled))
            let generation = try XCTUnwrap(result["generationConfig"] as? [String: Any])
            let thinking = try XCTUnwrap(generation["thinkingConfig"] as? [String: Int])
            XCTAssertEqual(thinking["thinkingBudget"], enabled ? 8192 : 128)
            XCTAssertGreaterThan(try XCTUnwrap(generation["maxOutputTokens"] as? Int), try XCTUnwrap(thinking["thinkingBudget"]))
        }
    }

    func testAnthropicBudgetHeadersAndExplicitDisable() throws {
        var caps = ModelCapabilities(); caps.reasoning = .anthropicBudget; caps.supportsTemperature = true
        for enabled in [false, true] {
            let request = try transport.makeRequest(messages: [AIMessage(role: .system, text: "sys"), AIMessage(role: .user, text: "hi")],
                config: config(.anthropic, caps: caps, enabled: enabled))
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(result["system"] as? String, "sys")
            XCTAssertEqual((result["thinking"] as? [String: Any])?["type"] as? String, enabled ? "enabled" : "disabled")
            if enabled {
                XCTAssertNil(result["temperature"])
                XCTAssertGreaterThan(try XCTUnwrap(result["max_tokens"] as? Int), caps.thinkingBudget)
            }
        }
        caps.thinkingBudget = 100
        XCTAssertThrowsError(try body(config(.anthropic, caps: caps, enabled: true)))
    }

    func testAdaptiveReasoningSupportsLowEffortAndExplicitDisable() throws {
        var caps = ModelCapabilities(); caps.reasoning = .anthropicAdaptive
        let low = try body(config(.anthropic, caps: caps))
        XCTAssertEqual((low["thinking"] as? [String: String])?["type"], "adaptive")
        XCTAssertEqual((low["output_config"] as? [String: String])?["effort"], "low")
        caps.offValue = "disabled"
        let off = try body(config(.anthropic, caps: caps))
        XCTAssertEqual((off["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertNil(off["output_config"])
    }

    func testCapabilitiesValidatedBeforeSending() throws {
        var caps = ModelCapabilities(); caps.reasoning = .geminiBudget
        XCTAssertThrowsError(try body(config(caps: caps)))
        caps.reasoning = .effort; caps.offValue = ""
        XCTAssertThrowsError(try body(config(caps: caps)))
        caps = ModelCapabilities(); caps.outputTokenLimit = -1
        XCTAssertThrowsError(try body(config(caps: caps)))
    }

    func testImagePayloadForAllProtocolsAndTextOnlyRejection() throws {
        let image = Data([1, 2, 3])
        XCTAssertThrowsError(try body(config(), image: image))
        for apiProtocol in AIProtocol.allCases {
            var caps = ModelCapabilities(); caps.supportsImages = true
            let result = try body(config(apiProtocol, caps: caps), image: image)
            let json = String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8) ?? ""
            XCTAssertTrue(json.contains("AQID"))
            if apiProtocol == .anthropic {
                let messages = try XCTUnwrap(result["messages"] as? [[String: Any]])
                let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
                let source = try XCTUnwrap(content.last?["source"] as? [String: Any])
                XCTAssertEqual(source["media_type"] as? String, "image/png")
            }
        }
    }

    func testOptionalJSONAndTemperature() throws {
        var caps = ModelCapabilities(); caps.supportsJSONMode = true; caps.supportsTemperature = true
        caps.reasoning = .unsupported
        let result = try body(config(caps: caps))
        XCTAssertEqual((result["response_format"] as? [String: String])?["type"], "json_object")
        XCTAssertEqual(result["temperature"] as? Double, 0.3)
        let gemini = try body(config(.gemini, caps: caps))
        XCTAssertEqual((gemini["generationConfig"] as? [String: Any])?["responseMimeType"] as? String, "application/json")
    }

    func testTemperatureSupportCanDifferBetweenReasoningStates() throws {
        var caps = ModelCapabilities()
        caps.supportsTemperature = true; caps.reasoning = .effort; caps.offValue = "none"
        XCTAssertNotNil(try body(config(caps: caps, enabled: false))["temperature"])
        XCTAssertNil(try body(config(caps: caps, enabled: true))["temperature"])
        caps.supportsTemperatureDuringReasoning = true
        XCTAssertNotNil(try body(config(caps: caps, enabled: true))["temperature"])
    }

    func testOnlyFinalAnswerBlocksAreReturned() throws {
        let cases: [(AIProtocol, String, String)] = [
            (.chatCompletions, #"{"choices":[{"message":{"reasoning_content":"secret","content":[{"type":"text","text":"hello "},{"type":"text","text":"world"}]}}]}"#, "hello world"),
            (.gemini, #"{"candidates":[{"content":{"parts":[{"thought":true,"text":"secret"},{"thought":false,"text":"hello "},{"text":"world"}]}}]}"#, "hello world"),
            (.anthropic, #"{"content":[{"type":"thinking","thinking":"secret"},{"type":"text","text":"hello "},{"type":"text","text":"world"}]}"#, "hello world"),
            (.chatCompletions, #"{"choices":[{"message":{"content":"<think>secret</think>final"}}]}"#, "final")
        ]
        for (apiProtocol, response, expected) in cases {
            XCTAssertEqual(try transport.parseResponse(Data(response.utf8), apiProtocol: apiProtocol), expected)
        }
        XCTAssertThrowsError(try transport.parseResponse(Data(#"{"content":[{"type":"thinking","thinking":"secret"}]}"#.utf8), apiProtocol: .anthropic))
    }

    func testTruncatedResponsesAreNotAcceptedAsResults() {
        let cases: [(AIProtocol, String)] = [
            (.chatCompletions, #"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#),
            (.gemini, #"{"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[{"text":"partial"}]}}]}"#),
            (.anthropic, #"{"stop_reason":"max_tokens","content":[{"type":"text","text":"partial"}]}"#)
        ]
        for (apiProtocol, response) in cases {
            XCTAssertThrowsError(try transport.parseResponse(Data(response.utf8), apiProtocol: apiProtocol)) { error in
                guard case AIServiceError.truncated = error else { return XCTFail("Wrong error") }
            }
        }
    }

    func testMalformedResponseIsNotRetried() {
        XCTAssertThrowsError(try transport.parseResponse(Data("not json".utf8), apiProtocol: .chatCompletions)) { error in
            guard let serviceError = error as? AIServiceError else { return XCTFail("Wrong error") }
            XCTAssertFalse(serviceError.shouldRetry)
        }
    }

    func testDeepThinkingPlanDoesNotTreatUnknownAsNonReasoning() {
        for reasoning in [ReasoningControl.serviceDefault, .unsupported, .alwaysOn, .effort] {
            var caps = ModelCapabilities(); caps.reasoning = reasoning
            let service = ResolvedAIService(provider: .custom, apiProtocol: .chatCompletions, baseURL: "", apiKey: "", model: "x", capabilities: caps)
            XCTAssertEqual(service.shouldEnhanceReview(mode: .defaultTranslation, deepThinking: true), reasoning == .unsupported)
            XCTAssertFalse(service.shouldEnhanceReview(mode: .defaultTranslation, deepThinking: false))
            XCTAssertFalse(service.shouldEnhanceReview(mode: .temporaryCustom, deepThinking: true))
        }
    }

    func testPromptOutputStructureIsStableAcrossThinkingPreferences() {
        let builder = TranslationPromptBuilder()
        for enabled in [false, true] {
            let prompt = builder.buildSystemPrompt(withLearnedRules: false, enhanceReview: enabled)
            XCTAssertFalse(prompt.contains("thinking_process"))
            XCTAssertTrue(prompt.contains("translation_result"))
            XCTAssertEqual(prompt.contains("check ambiguous meanings"), enabled)
        }
        let preset = PromptPreset(id: UUID(), name: "test", inputPerception: "text", outputInstruction: "summarize")
        XCTAssertFalse(PresetPromptBuilder().buildSystemPrompt(preset: preset).contains("thinking_process"))
        XCTAssertFalse(CustomPromptBuilder().buildSystemPrompt(inputContext: nil, outputRequirement: nil).contains("thinking_process"))
    }

    func testOldSettingsAndImageSelectionRemainIndependent() throws {
        let name = "YisiTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("OpenAI", forKey: "api_provider")
        defaults.set("text-model", forKey: "openai_model")
        defaults.set("text-test-key", forKey: "openai_api_key")
        defaults.set(false, forKey: "apply_api_to_image_mode")
        defaults.set("Gemini", forKey: "image_api_provider")
        defaults.set("image-model", forKey: "image_gemini_model")
        defaults.set("image-test-key", forKey: "image_gemini_api_key")
        XCTAssertEqual(AIConfigurationStore.resolve(defaults: defaults).model, "text-model")
        XCTAssertEqual(AIConfigurationStore.resolve(image: true, defaults: defaults).model, "image-model")
        XCTAssertEqual(AIConfigurationStore.resolve(image: true, defaults: defaults).apiKey, "image-test-key")
        defaults.set(true, forKey: "apply_api_to_image_mode")
        XCTAssertEqual(AIConfigurationStore.resolve(image: true, defaults: defaults).model, "text-model")
        XCTAssertEqual(AIConfigurationStore.resolve(image: true, defaults: defaults).apiKey, "text-test-key")
    }

    func testCustomConfigurationAndModelProfilesRoundTrip() throws {
        let name = "YisiTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = CustomServiceConfiguration()
        settings.baseURL = "https://example.com/v1"; settings.model = "new-model"
        settings.capabilities.reasoning = .effort
        AIConfigurationStore.saveCustom(settings, image: false, defaults: defaults)
        AIConfigurationStore.saveCustomCapabilities(settings, image: false, defaults: defaults)
        XCTAssertEqual(AIConfigurationStore.custom(image: false, defaults: defaults), settings)
        XCTAssertEqual(AIConfigurationStore.customCapabilities(settings, image: false, defaults: defaults).reasoning, .effort)
        settings.model = "other-model"
        XCTAssertEqual(AIConfigurationStore.customCapabilities(settings, image: false, defaults: defaults).reasoning, .serviceDefault)
        XCTAssertEqual(AIConfigurationStore.custom(image: true, defaults: defaults), CustomServiceConfiguration())
        let key = AIConfigurationStore.customKey(image: false)
        let json = String(data: try XCTUnwrap(defaults.data(forKey: key)), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("apiKey"))
    }

    func testHttpErrorsRedactCredentialsAndClassifyRetry() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AIHTTPTransport(session: session).send(messages: [AIMessage(role: .user, text: "hi")], config: config())
            XCTFail("Expected error")
        } catch let error as AIServiceError {
            XCTAssertFalse(error.localizedDescription.contains("test-key"))
            XCTAssertFalse(error.shouldRetry)
        }
        XCTAssertTrue(AIServiceError.http(429, "retry").shouldRetry)
        XCTAssertTrue(AIServiceError.http(503, "retry").shouldRetry)
        XCTAssertFalse(AIServiceError.http(400, "bad config").shouldRetry)
    }
}

private final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("Invalid credential test-key".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
