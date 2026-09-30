import Foundation

enum AIServiceError: LocalizedError {
    case configuration(String)
    case http(Int, String)
    case invalidResponse
    case truncated
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message.localized
        case .http(let status, let message): return "HTTP \(status): \(message)"
        case .invalidResponse: return "The service returned an invalid response.".localized
        case .truncated: return "The response reached the output limit. Increase the token limit in Advanced Adaptation.".localized
        case .emptyResponse: return "The service returned no final answer.".localized
        }
    }

    var shouldRetry: Bool {
        if case .http(let status, _) = self { return status == 429 || status >= 500 }
        return false
    }
}

/// All providers share request validation, transport and final-answer parsing.
struct AIHTTPTransport {
    var session: URLSession = .shared

    func send(messages: [AIMessage], config: AIRequestConfig) async throws -> String {
        let request = try makeRequest(messages: messages, config: config)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            // Never surface credentials echoed by an upstream error.
            var message = String(data: data, encoding: .utf8) ?? "Unknown error"
            if !config.apiKey.isEmpty { message = message.replacingOccurrences(of: config.apiKey, with: "[redacted]") }
            throw AIServiceError.http(response.statusCode, String(message.prefix(1000)))
        }
        return try parseResponse(data, apiProtocol: config.apiProtocol)
    }

    func makeRequest(messages: [AIMessage], config: AIRequestConfig) throws -> URLRequest {
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.configuration("Enter a model ID.")
        }
        if messages.contains(where: { $0.content.image != nil }) && !config.capabilities.supportsImages {
            throw AIServiceError.configuration("This model is not configured for images. Enable image support or choose System OCR.")
        }
        let caps = config.capabilities
        guard caps.outputTokenLimit > 0, caps.outputTokenLimit <= 1_000_000 else {
            throw AIServiceError.configuration("Output token limit must be between 1 and 1000000.")
        }
        guard ReasoningControl.options(for: config.apiProtocol).contains(caps.reasoning) else {
            throw AIServiceError.configuration("The reasoning control does not match the selected protocol.")
        }
        let url = try endpoint(baseURL: config.baseURL, apiProtocol: config.apiProtocol, model: config.model)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            switch config.apiProtocol {
            case .gemini: request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
            case .anthropic: request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            case .chatCompletions: request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        if config.apiProtocol == .anthropic { request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version") }
        request.httpBody = try JSONSerialization.data(withJSONObject: makeBody(messages: messages, config: config))
        return request
    }

    func endpoint(baseURL: String, apiProtocol: AIProtocol, model: String) throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw AIServiceError.configuration("Enter a valid HTTP or HTTPS base URL without credentials, query or fragment.")
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix: String
        switch apiProtocol {
        case .chatCompletions: suffix = "chat/completions"
        case .anthropic: suffix = "messages"
        case .gemini:
            // A model ID is one path segment, never a URL or a query string.
            let model = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/?#%:")
            guard let escaped = model.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw AIServiceError.configuration("Enter a model ID.")
            }
            suffix = "models/\(escaped):generateContent"
        }
        if basePath == suffix || basePath.hasSuffix("/\(suffix)") {
            components.percentEncodedPath = "/\(basePath)"
        } else {
            components.percentEncodedPath = "/" + ([basePath, suffix].filter { !$0.isEmpty }.joined(separator: "/"))
        }
        guard let url = components.url else { throw AIServiceError.configuration("Invalid service URL.") }
        return url
    }

    func makeBody(messages: [AIMessage], config: AIRequestConfig) throws -> [String: Any] {
        let caps = config.capabilities
        // Effort-controlled models spend completion tokens on both reasoning and the answer.
        // Keep room for the answer, including when the "off" preference still maps to low effort.
        let needsReserve = caps.nativeReasoningActive(enabled: config.enableNativeReasoning) &&
            caps.reasoning != .geminiBudget && caps.reasoning != .anthropicBudget
        let reserve = needsReserve ? min(4096, caps.outputTokenLimit / 2) : 0
        let tokens = min(max(1, config.maxTokens), caps.outputTokenLimit - reserve) + reserve
        var body: [String: Any]
        switch config.apiProtocol {
        case .chatCompletions:
            body = ["model": config.model, "messages": messages.map { message -> [String: Any] in
                var content: Any = message.content.text
                if let image = message.content.image {
                    content = [["type": "text", "text": message.content.text],
                               ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(image.base64EncodedString())"]]]
                }
                return ["role": message.role.rawValue, "content": content]
            }, caps.tokenLimitField.rawValue: tokens]
            if caps.supportsJSONMode { body["response_format"] = ["type": "json_object"] }
        case .gemini:
            let contents = messages.filter { $0.role != .system }.map { message -> [String: Any] in
                var parts: [[String: Any]] = [["text": message.content.text]]
                if let image = message.content.image {
                    parts.append(["inline_data": ["mime_type": "image/png", "data": image.base64EncodedString()]])
                }
                return ["role": message.role == .assistant ? "model" : "user", "parts": parts]
            }
            var generation: [String: Any] = ["maxOutputTokens": tokens]
            if caps.supportsJSONMode { generation["responseMimeType"] = "application/json" }
            body = ["contents": contents, "generationConfig": generation]
        case .anthropic:
            let conversation = messages.filter { $0.role != .system }.map { message -> [String: Any] in
                var content: [[String: Any]] = [["type": "text", "text": message.content.text]]
                if let image = message.content.image {
                    content.append(["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": image.base64EncodedString()]])
                }
                return ["role": message.role.rawValue, "content": content]
            }
            body = ["model": config.model, "messages": conversation, "max_tokens": tokens]
        }
        let system = messages.filter { $0.role == .system }.map { $0.content.text }.joined(separator: "\n\n")
        if !system.isEmpty {
            if config.apiProtocol == .gemini { body["systemInstruction"] = ["parts": [["text": system]]] }
            if config.apiProtocol == .anthropic { body["system"] = system }
        }
        if caps.supportsTemperature && (!caps.nativeReasoningActive(enabled: config.enableNativeReasoning) || caps.supportsTemperatureDuringReasoning) {
            if config.apiProtocol == .gemini {
                var generation = body["generationConfig"] as? [String: Any] ?? [:]
                generation["temperature"] = config.temperature
                body["generationConfig"] = generation
            } else { body["temperature"] = config.temperature }
        }
        try applyReasoning(body: &body, config: config)
        return body
    }

    private func applyReasoning(body: inout [String: Any], config: AIRequestConfig) throws {
        let caps = config.capabilities
        let enabled = config.enableNativeReasoning
        let value = (enabled ? caps.onValue : caps.offValue).trimmingCharacters(in: .whitespacesAndNewlines)
        switch caps.reasoning {
        case .serviceDefault, .unsupported, .alwaysOn: break
        case .effort: body["reasoning_effort"] = value
        case .thinkingType: body["thinking"] = ["type": enabled ? "enabled" : "disabled"]
        case .enableThinking: body["enable_thinking"] = enabled
        case .geminiLevel, .geminiBudget:
            var generation = body["generationConfig"] as? [String: Any] ?? [:]
            if caps.reasoning == .geminiLevel {
                generation["thinkingConfig"] = ["thinkingLevel": value]
            } else {
                let budget = enabled ? caps.thinkingBudget : caps.minimumThinkingBudget
                guard budget >= 0, budget < caps.outputTokenLimit else {
                    throw AIServiceError.configuration("Thinking budget must be non-negative and below the output token limit.")
                }
                generation["thinkingConfig"] = ["thinkingBudget": budget]
                generation["maxOutputTokens"] = min(caps.outputTokenLimit, config.maxTokens + budget)
            }
            body["generationConfig"] = generation
        case .anthropicBudget:
            if enabled {
                guard caps.thinkingBudget >= 1024, caps.thinkingBudget < caps.outputTokenLimit else {
                    throw AIServiceError.configuration("Anthropic thinking budget must be at least 1024 and below the output token limit.")
                }
                body["thinking"] = ["type": "enabled", "budget_tokens": caps.thinkingBudget]
                body["max_tokens"] = min(caps.outputTokenLimit, config.maxTokens + caps.thinkingBudget)
                body.removeValue(forKey: "temperature")
            } else { body["thinking"] = ["type": "disabled"] }
        case .anthropicAdaptive:
            body["thinking"] = ["type": value == "disabled" ? "disabled" : "adaptive"]
            if value != "disabled" { body["output_config"] = ["effort": value] }
            body.removeValue(forKey: "temperature")
        }
        if [.effort, .geminiLevel, .anthropicAdaptive].contains(caps.reasoning) && value.isEmpty {
            throw AIServiceError.configuration("Enter both the enabled and disabled reasoning values.")
        }
    }

    func parseResponse(_ data: Data, apiProtocol: AIProtocol) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw AIServiceError.invalidResponse }
        let text: String
        switch apiProtocol {
        case .chatCompletions:
            guard let choice = (json["choices"] as? [[String: Any]])?.first,
                  let message = choice["message"] as? [String: Any] else { throw AIServiceError.invalidResponse }
            if choice["finish_reason"] as? String == "length" { throw AIServiceError.truncated }
            if let content = message["content"] as? String { text = content }
            else { text = textBlocks(message["content"]) }
        case .gemini:
            guard let candidate = (json["candidates"] as? [[String: Any]])?.first,
                  let content = candidate["content"] as? [String: Any] else { throw AIServiceError.invalidResponse }
            if candidate["finishReason"] as? String == "MAX_TOKENS" { throw AIServiceError.truncated }
            let parts = content["parts"] as? [[String: Any]] ?? []
            text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        case .anthropic:
            if json["stop_reason"] as? String == "max_tokens" { throw AIServiceError.truncated }
            text = textBlocks(json["content"])
        }
        let cleaned = text.replacingOccurrences(of: #"<think>[\s\S]*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.hasPrefix("<think>") else { throw AIServiceError.emptyResponse }
        return cleaned
    }

    private func textBlocks(_ value: Any?) -> String {
        (value as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }.joined()
    }
}
