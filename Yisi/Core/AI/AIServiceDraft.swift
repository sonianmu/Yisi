import Foundation

struct AIServiceDraft: Equatable {
    var provider: APIProvider
    var apiKey: String
    var model: String
    var baseURL: String
    var apiProtocol: AIProtocol
    var capabilities: ModelCapabilities
    var deepThinking: Bool
    let image: Bool

    static func load(image: Bool, provider selected: APIProvider? = nil, defaults: UserDefaults = .standard,
                     readCredential: (Bool) -> String = { image in
                         KeychainHelper.shared.read(service: "com.yisi.app", account: AIConfigurationStore.credentialAccount(image: image))
                             .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                     }) -> Self {
        let prefix = image ? "image_" : ""
        let provider = selected ?? APIProvider(rawValue: defaults.string(forKey: "\(prefix)api_provider") ?? AppDefaults.apiProvider) ?? .zhipu
        let template = AIConfigurationStore.presetConnection(provider: provider)
        let custom = AIConfigurationStore.custom(image: image, defaults: defaults)
        let model = provider == .custom ? custom.model : defaults.string(forKey: "\(prefix)\(template.keyPrefix)_model") ?? ""
        var capabilities = provider == .custom ? custom.capabilities : AIConfigurationStore.capabilities(provider: provider, model: model, image: image, defaults: defaults)
        if image { capabilities.supportsImages = true }
        return Self(provider: provider,
            apiKey: provider == .custom ? readCredential(image) : defaults.string(forKey: "\(prefix)\(template.keyPrefix)_api_key") ?? "",
            model: model, baseURL: provider == .custom ? custom.baseURL : template.baseURL,
            apiProtocol: provider == .custom ? custom.apiProtocol : template.apiProtocol,
            capabilities: capabilities,
            deepThinking: defaults.object(forKey: AppDefaults.Keys.enableDeepThinking) as? Bool ?? AppDefaults.enableDeepThinking, image: image)
    }

    var connection: ResolvedAIService {
        ResolvedAIService(provider: provider, apiProtocol: apiProtocol,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines), capabilities: capabilities)
    }

    func validate() throws {
        guard !connection.apiKey.isEmpty else { throw AIServiceError.configuration("Enter an API key.") }
        guard !connection.model.isEmpty else { throw AIServiceError.configuration("Enter a model ID.") }
        guard !connection.baseURL.isEmpty else { throw AIServiceError.configuration("Enter the API base URL.") }
    }

    @MainActor func testAndSave(defaults: UserDefaults = .standard,
                     send: ([AIMessage], AIRequestConfig) async throws -> String = { messages, config in
                         try await AIHTTPTransport().send(messages: messages, config: config)
                     },
                     saveCredential: (Data, Bool) throws -> Void = { data, image in
                         try KeychainHelper.shared.saveChecked(data, service: "com.yisi.app",
                             account: AIConfigurationStore.credentialAccount(image: image))
                     }) async throws -> String {
        try validate()
        let testImage = image ? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAJklEQVR4nO3NMQ0AAAwDoPo33arYsQQMkB6LQCAQCAQCgUAg+BIMi1X0pjxKe0gAAAAASUVORK5CYII=") : nil
        let messages = [AIMessage(role: .user, text: "Reply with OK to confirm the connection.", image: testImage)]
        let response = try await send(messages, connection.requestConfig(temperature: 0.1, maxTokens: 1024, deepThinking: deepThinking))
        try Task.checkCancellation()
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIServiceError.emptyResponse }
        let prefix = image ? "image_" : ""
        if provider == .custom {
            // Commit the credential first; a Keychain failure must leave the old service selected.
            try saveCredential(Data(connection.apiKey.utf8), image)
            var settings = CustomServiceConfiguration()
            settings.baseURL = connection.baseURL
            settings.apiProtocol = apiProtocol
            settings.model = connection.model
            settings.capabilities = capabilities
            AIConfigurationStore.saveCustom(settings, image: image, defaults: defaults)
            AIConfigurationStore.saveCustomCapabilities(settings, image: image, defaults: defaults)
        } else {
            let template = AIConfigurationStore.presetConnection(provider: provider)
            defaults.set(connection.apiKey, forKey: "\(prefix)\(template.keyPrefix)_api_key")
            defaults.set(connection.model, forKey: "\(prefix)\(template.keyPrefix)_model")
            AIConfigurationStore.saveCapabilities(capabilities, provider: provider, model: connection.model, image: image, defaults: defaults)
        }
        defaults.set(provider.rawValue, forKey: "\(prefix)api_provider")
        defaults.set(deepThinking, forKey: AppDefaults.Keys.enableDeepThinking)
        defaults.set("ai", forKey: AppDefaults.Keys.translationEngine)
        return response
    }
}
