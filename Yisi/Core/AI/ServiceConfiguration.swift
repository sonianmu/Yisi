import Foundation

enum AIProtocol: String, Codable, CaseIterable {
    case chatCompletions = "OpenAI Compatible"
    case gemini = "Gemini Native"
    case anthropic = "Anthropic Messages"
}

enum ReasoningControl: String, Codable, CaseIterable {
    case serviceDefault = "Service Default"
    case unsupported = "No Native Reasoning"
    case alwaysOn = "Always On"
    case effort = "Reasoning Effort"
    case thinkingType = "Thinking Type"
    case enableThinking = "Enable Thinking"
    case geminiBudget = "Gemini Thinking Budget"
    case geminiLevel = "Gemini Thinking Level"
    case anthropicBudget = "Anthropic Thinking Budget"
    case anthropicAdaptive = "Anthropic Adaptive Thinking"

    static func options(for apiProtocol: AIProtocol) -> [Self] {
        let common: [Self] = [.serviceDefault, .unsupported, .alwaysOn]
        switch apiProtocol {
        case .chatCompletions: return common + [.effort, .thinkingType, .enableThinking]
        case .gemini: return common + [.geminiBudget, .geminiLevel]
        case .anthropic: return common + [.anthropicBudget, .anthropicAdaptive]
        }
    }
}

enum TokenLimitField: String, Codable, CaseIterable {
    case maxTokens = "max_tokens"
    case maxCompletionTokens = "max_completion_tokens"
}

/// Capabilities describe the selected model at this endpoint, independently of its name.
struct ModelCapabilities: Codable, Equatable {
    var supportsImages = false
    var supportsTemperature = false
    var supportsTemperatureDuringReasoning = false
    var supportsJSONMode = false
    var tokenLimitField: TokenLimitField = .maxTokens
    var outputTokenLimit = 16384
    var reasoning: ReasoningControl = .serviceDefault
    var onValue = "high"
    var offValue = "low"
    var thinkingBudget = 8192
    var minimumThinkingBudget = 0

    func nativeReasoningActive(enabled: Bool) -> Bool {
        let value = (enabled ? onValue : offValue).trimmingCharacters(in: .whitespacesAndNewlines)
        switch reasoning {
        case .unsupported: return false
        case .serviceDefault, .alwaysOn: return true
        case .thinkingType, .enableThinking, .anthropicBudget: return enabled
        case .geminiBudget: return enabled ? thinkingBudget > 0 : minimumThinkingBudget > 0
        case .effort, .geminiLevel: return value != "none"
        case .anthropicAdaptive: return value != "disabled"
        }
    }

    var reasoningNotice: String {
        switch reasoning {
        case .serviceDefault: return "Reasoning follows the service default. Configure capabilities to control it."
        case .unsupported: return "No native reasoning. Deep thinking adds a translation quality check."
        case .alwaysOn: return "This model always reasons; the switch cannot disable it."
        case .effort, .geminiLevel, .anthropicAdaptive:
            return offValue == "none" || offValue == "disabled"
                ? "Deep thinking switches native reasoning on or off."
                : "Turning off deep thinking uses the configured lower effort; reasoning remains enabled."
        case .geminiBudget:
            return minimumThinkingBudget == 0
                ? "Deep thinking switches native reasoning on or off."
                : "This model cannot disable reasoning; turning it off uses the minimum budget."
        case .thinkingType, .enableThinking, .anthropicBudget:
            return "Deep thinking switches native reasoning on or off."
        }
    }
}

struct CustomServiceConfiguration: Codable, Equatable {
    var baseURL = ""
    var apiProtocol: AIProtocol = .chatCompletions
    var model = ""
    var capabilities = ModelCapabilities()

    var modelIdentity: String {
        [apiProtocol.rawValue, baseURL.trimmingCharacters(in: .whitespacesAndNewlines), model].joined(separator: "|")
    }
}

struct ResolvedAIService {
    let provider: APIProvider
    let apiProtocol: AIProtocol
    let baseURL: String
    let apiKey: String
    let model: String
    let capabilities: ModelCapabilities

    func requestConfig(temperature: Double, maxTokens: Int, deepThinking: Bool) -> AIRequestConfig {
        AIRequestConfig(apiKey: apiKey, model: model, temperature: temperature,
                        maxTokens: maxTokens, enableNativeReasoning: deepThinking,
                        apiProtocol: apiProtocol, baseURL: baseURL, capabilities: capabilities)
    }

    func shouldEnhanceReview(mode: PromptMode, deepThinking: Bool) -> Bool {
        mode == .defaultTranslation && deepThinking && capabilities.reasoning == .unsupported
    }
}

enum AIConfigurationStore {
    static func customKey(image: Bool) -> String { image ? "image_custom_service" : "custom_service" }
    static func credentialAccount(image: Bool) -> String { image ? "image_custom_api_key" : "custom_api_key" }

    static func custom(image: Bool, defaults: UserDefaults = .standard) -> CustomServiceConfiguration {
        guard let data = defaults.data(forKey: customKey(image: image)),
              let value = try? JSONDecoder().decode(CustomServiceConfiguration.self, from: data) else {
            return CustomServiceConfiguration()
        }
        return value
    }

    static func saveCustom(_ value: CustomServiceConfiguration, image: Bool, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: customKey(image: image)) }
    }

    static func customCapabilities(_ value: CustomServiceConfiguration, image: Bool, defaults: UserDefaults = .standard) -> ModelCapabilities {
        let key = "\(customKey(image: image)).capabilities.\(value.modelIdentity)"
        guard let data = defaults.data(forKey: key), let caps = try? JSONDecoder().decode(ModelCapabilities.self, from: data) else {
            return ModelCapabilities()
        }
        return caps
    }

    static func saveCustomCapabilities(_ value: CustomServiceConfiguration, image: Bool, defaults: UserDefaults = .standard) {
        if !value.model.isEmpty, let data = try? JSONEncoder().encode(value.capabilities) {
            defaults.set(data, forKey: "\(customKey(image: image)).capabilities.\(value.modelIdentity)")
        }
    }

    static func overrideKey(provider: APIProvider, model: String, image: Bool) -> String {
        "model_capabilities.\(image ? "image" : "text").\(provider.rawValue).\(model)"
    }

    static func capabilities(provider: APIProvider, model: String, image: Bool, defaults: UserDefaults = .standard) -> ModelCapabilities {
        let key = overrideKey(provider: provider, model: model, image: image)
        if let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(ModelCapabilities.self, from: data) {
            return value
        }
        return presetCapabilities(provider: provider, model: model)
    }

    static func saveCapabilities(_ value: ModelCapabilities, provider: APIProvider, model: String, image: Bool) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: overrideKey(provider: provider, model: model, image: image))
        }
    }

    static func resolve(image: Bool = false, defaults: UserDefaults = .standard) -> ResolvedAIService {
        let separateImage = image && !(defaults.object(forKey: "apply_api_to_image_mode") == nil || defaults.bool(forKey: "apply_api_to_image_mode"))
        let prefix = separateImage ? "image_" : ""
        let provider = APIProvider(rawValue: defaults.string(forKey: "\(prefix)api_provider") ?? AppDefaults.apiProvider) ?? .zhipu
        if provider == .custom {
            let settings = custom(image: separateImage, defaults: defaults)
            let keyData = KeychainHelper.shared.read(service: "com.yisi.app", account: credentialAccount(image: separateImage))
            return ResolvedAIService(provider: provider, apiProtocol: settings.apiProtocol, baseURL: settings.baseURL,
                                     apiKey: keyData.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                                     model: settings.model, capabilities: settings.capabilities)
        }
        let template = presetConnection(provider: provider)
        let model = defaults.string(forKey: "\(prefix)\(template.keyPrefix)_model") ?? template.model
        return ResolvedAIService(provider: provider, apiProtocol: template.apiProtocol, baseURL: template.baseURL,
                                 apiKey: defaults.string(forKey: "\(prefix)\(template.keyPrefix)_api_key") ?? "",
                                 model: model, capabilities: capabilities(provider: provider, model: model, image: separateImage, defaults: defaults))
    }

    static func presetConnection(provider: APIProvider) -> (keyPrefix: String, apiProtocol: AIProtocol, baseURL: String, model: String) {
        switch provider {
        case .openai: return ("openai", .chatCompletions, "https://api.openai.com/v1", AppDefaults.openaiModel)
        case .gemini: return ("gemini", .gemini, "https://generativelanguage.googleapis.com/v1beta", AppDefaults.geminiModel)
        case .zhipu: return ("zhipu", .chatCompletions, "https://open.bigmodel.cn/api/paas/v4", AppDefaults.zhipuModel)
        case .minimax: return ("minimax", .anthropic, "https://api.minimaxi.com/anthropic/v1", AppDefaults.minimaxModel)
        case .deepseek: return ("deepseek", .chatCompletions, "https://api.deepseek.com", AppDefaults.deepseekModel)
        case .custom: return ("custom", .chatCompletions, "", "")
        }
    }

    /// Small backward-compatible presets. Unrecognized models keep unknown capabilities.
    static func presetCapabilities(provider: APIProvider, model: String) -> ModelCapabilities {
        var value = ModelCapabilities()
        let model = model.lowercased()
        switch provider {
        case .openai:
            if model.hasPrefix("gpt-4") {
                value.supportsImages = model.hasPrefix("gpt-4o") || model.hasPrefix("gpt-4.1")
                value.supportsTemperature = true
                value.supportsJSONMode = value.supportsImages; value.reasoning = .unsupported
            } else if model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") {
                value.reasoning = model == "o1-mini" || model == "o1-preview" ? .alwaysOn : .effort
                value.tokenLimitField = .maxCompletionTokens
            } else {
                value.tokenLimitField = .maxCompletionTokens
            }
        case .gemini:
            value.supportsTemperatureDuringReasoning = true
            if model.hasPrefix("gemini-2.5-") {
                value.reasoning = .geminiBudget
                value.minimumThinkingBudget = model.hasPrefix("gemini-2.5-pro") ? 128 : 0
                value.supportsImages = true; value.supportsTemperature = true; value.supportsJSONMode = true
            } else if model.hasPrefix("gemini-3-") {
                value.reasoning = .geminiLevel
                value.supportsImages = true; value.supportsTemperature = true; value.supportsJSONMode = true
            } else if model.hasPrefix("gemini-2.0-") {
                value.reasoning = .unsupported
                value.supportsImages = true; value.supportsTemperature = true; value.supportsJSONMode = true
            }
        case .zhipu:
            if model.hasPrefix("glm-4.5") || model.hasPrefix("glm-4.6") {
                value.reasoning = .thinkingType; value.supportsTemperature = true
                value.supportsTemperatureDuringReasoning = true
                value.supportsImages = model.contains("4.5v") || model.contains("4.6v")
            }
        case .deepseek:
            if model == "deepseek-chat" || model == "deepseek-reasoner" {
                value.reasoning = .thinkingType
            }
        case .minimax:
            if ["minimax-m2.5", "minimax-m2.1", "minimax-m1"].contains(model) { value.reasoning = .alwaysOn }
        case .custom: break
        }
        return value
    }
}
