import SwiftUI

struct CustomServiceForm: View {
    let imageConfiguration: Bool
    @State private var settings: CustomServiceConfiguration
    @State private var apiKey = ""
    @State private var keyStatus = ""
    @State private var keySaved = false
    @State private var savedAPIKey = ""
    @AppStorage(AppDefaults.Keys.enableDeepThinking) private var deepThinking = AppDefaults.enableDeepThinking

    init(imageConfiguration: Bool) {
        self.imageConfiguration = imageConfiguration
        _settings = State(initialValue: AIConfigurationStore.custom(image: imageConfiguration))
    }

    private var connection: ResolvedAIService {
        ResolvedAIService(provider: .custom, apiProtocol: settings.apiProtocol, baseURL: settings.baseURL,
                          apiKey: apiKey, model: settings.model, capabilities: settings.capabilities)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            adaptationRow("Protocol") {
                CustomDropdown(selection: Binding(get: { settings.apiProtocol.rawValue }, set: { raw in
                    guard let value = AIProtocol(rawValue: raw), value != settings.apiProtocol else { return }
                    settings.apiProtocol = value
                    settings.capabilities = ModelCapabilities()
                }), options: AIProtocol.allCases.map(\.rawValue),
                   displayNames: AIProtocol.allCases.map { $0.rawValue.localized })
            }
            APIKeyInput(label: "Base URL".localized, text: $settings.baseURL,
                        placeholder: "https://example.com/v1", isSecure: false)
            Text("Use the API base path, including /v1 or /v1beta when required.".localized)
                .font(.system(size: 11, design: .serif)).foregroundStyle(.secondary)
            APIKeyInput(label: "API Key".localized, text: $apiKey, placeholder: "Optional for local services".localized)
            HStack(spacing: 10) {
                Button("Save API Key".localized, action: saveKey)
                    .buttonStyle(.borderless)
                if !keyStatus.isEmpty {
                    Text(keyStatus.localized).foregroundStyle(keySaved ? Color.secondary : Color.red)
                }
            }
            .font(.system(size: 11, design: .serif))
            APIKeyInput(label: "Model".localized, text: $settings.model, placeholder: "Enter any model ID".localized, isSecure: false)
            CapabilityEditor(capabilities: $settings.capabilities, apiProtocol: settings.apiProtocol)
            ConnectionTestButton(connection: connection, deepThinking: deepThinking, testImage: imageConfiguration)
                .id("\(settings).\(apiKey.hashValue).\(deepThinking)")
        }
        .onAppear {
            if let data = KeychainHelper.shared.read(service: "com.yisi.app", account: AIConfigurationStore.credentialAccount(image: imageConfiguration)) {
                savedAPIKey = String(data: data, encoding: .utf8) ?? ""
                apiKey = savedAPIKey
            }
        }
        .onChange(of: settings) { old, value in
            var value = value
            if old.modelIdentity != value.modelIdentity {
                AIConfigurationStore.saveCustomCapabilities(old, image: imageConfiguration)
                value.capabilities = AIConfigurationStore.customCapabilities(value, image: imageConfiguration)
                settings = value
            }
            AIConfigurationStore.saveCustom(value, image: imageConfiguration)
            AIConfigurationStore.saveCustomCapabilities(value, image: imageConfiguration)
        }
        .onChange(of: apiKey) { _, value in
            keySaved = value == savedAPIKey
            keyStatus = keySaved ? "" : "API key not saved. Save it before using this service."
        }
    }

    private func saveKey() {
        do {
            try KeychainHelper.shared.saveChecked(Data(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).utf8),
                service: "com.yisi.app", account: AIConfigurationStore.credentialAccount(image: imageConfiguration))
            keySaved = true
            savedAPIKey = apiKey
            keyStatus = "API key saved to Keychain."
        } catch {
            keySaved = false
            keyStatus = error.localizedDescription
        }
    }
}

struct ModelAdaptationForm: View {
    let provider: APIProvider
    let model: String
    let imageConfiguration: Bool
    @State private var capabilities: ModelCapabilities
    @AppStorage(AppDefaults.Keys.enableDeepThinking) private var deepThinking = AppDefaults.enableDeepThinking

    init(provider: APIProvider, model: String, imageConfiguration: Bool) {
        self.provider = provider
        self.model = model
        self.imageConfiguration = imageConfiguration
        _capabilities = State(initialValue: AIConfigurationStore.capabilities(provider: provider, model: model, image: imageConfiguration))
    }

    private var connection: ResolvedAIService {
        let template = AIConfigurationStore.presetConnection(provider: provider)
        let keyPrefix = imageConfiguration ? "image_" : ""
        return ResolvedAIService(provider: provider, apiProtocol: template.apiProtocol, baseURL: template.baseURL,
            apiKey: UserDefaults.standard.string(forKey: "\(keyPrefix)\(template.keyPrefix)_api_key") ?? "",
            model: model, capabilities: capabilities)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapabilityEditor(capabilities: $capabilities, apiProtocol: connection.apiProtocol)
            ConnectionTestButton(connection: connection, deepThinking: deepThinking, testImage: imageConfiguration)
                .id("\(capabilities).\(connection.apiKey.hashValue).\(deepThinking)")
        }
        .onChange(of: capabilities) { _, value in
            AIConfigurationStore.saveCapabilities(value, provider: provider, model: model, image: imageConfiguration)
        }
    }
}

private struct CapabilityEditor: View {
    @Binding var capabilities: ModelCapabilities
    let apiProtocol: AIProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capabilities.reasoningNotice.localized)
                .font(.system(size: 11, design: .serif))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Advanced Adaptation".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    adaptationRow("Reasoning Control") {
                        let options = ReasoningControl.options(for: apiProtocol)
                        CustomDropdown(selection: Binding(get: { capabilities.reasoning.rawValue }, set: { raw in
                            if let value = ReasoningControl(rawValue: raw) { capabilities.reasoning = value }
                        }), options: options.map(\.rawValue), displayNames: options.map { $0.rawValue.localized })
                    }
                    if [.effort, .geminiLevel, .anthropicAdaptive].contains(capabilities.reasoning) {
                        APIKeyInput(label: "Enabled Value".localized, text: $capabilities.onValue, placeholder: "high", isSecure: false)
                        APIKeyInput(label: "Disabled Value".localized, text: $capabilities.offValue, placeholder: "low / none / disabled", isSecure: false)
                        Text("Use values supported by this model. Low effort still enables reasoning.".localized)
                            .font(.system(size: 11, design: .serif)).foregroundStyle(.secondary)
                    }
                    if [.geminiBudget, .anthropicBudget].contains(capabilities.reasoning) {
                        integerRow("Thinking Budget", value: $capabilities.thinkingBudget)
                    }
                    if capabilities.reasoning == .geminiBudget {
                        integerRow("Minimum Budget", value: $capabilities.minimumThinkingBudget)
                    }
                    adaptationRow("Image Support") { ElegantToggle(isOn: $capabilities.supportsImages) }
                    adaptationRow("Temperature") { ElegantToggle(isOn: $capabilities.supportsTemperature) }
                    if capabilities.supportsTemperature && capabilities.reasoning != .unsupported {
                        adaptationRow("Temperature During Reasoning") {
                            ElegantToggle(isOn: $capabilities.supportsTemperatureDuringReasoning)
                        }
                    }
                    if apiProtocol != .anthropic {
                        adaptationRow("Native JSON Mode") { ElegantToggle(isOn: $capabilities.supportsJSONMode) }
                    }
                    if apiProtocol == .chatCompletions {
                        adaptationRow("Token Parameter") {
                            CustomDropdown(selection: Binding(get: { capabilities.tokenLimitField.rawValue }, set: { raw in
                                if let value = TokenLimitField(rawValue: raw) { capabilities.tokenLimitField = value }
                            }), options: TokenLimitField.allCases.map(\.rawValue))
                        }
                    }
                    integerRow("Output Token Limit", value: $capabilities.outputTokenLimit)
                    Text("Capabilities are saved for this model. Unknown models follow service defaults.".localized)
                        .font(.system(size: 11, design: .serif)).foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }
            .font(.system(size: 12, design: .serif))
        }
    }

    private func integerRow(_ title: String, value: Binding<Int>) -> some View {
        adaptationRow(title) {
            TextField("", value: value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 130)
                .accessibilityLabel(title.localized)
        }
    }
}

private struct ConnectionTestButton: View {
    let connection: ResolvedAIService
    let deepThinking: Bool
    let testImage: Bool
    @State private var task: Task<Void, Never>?
    @State private var testing = false
    @State private var status = ""
    @State private var succeeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button("Test Connection".localized, action: testConnection)
                    .buttonStyle(.borderless).disabled(testing)
                if testing { ProgressView().controlSize(.small) }
                Text("Sends a small test request using the current thinking preference.".localized)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !status.isEmpty {
                Text(status.localized).foregroundStyle(succeeded ? Color.secondary : Color.red)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 11, design: .serif))
        .onDisappear { task?.cancel() }
    }

    private func testConnection() {
        testing = true
        status = ""
        task = Task { @MainActor in
            defer { testing = false }
            do {
                // A small blank PNG exercises the selected image protocol without sending user content.
                let image = testImage ? Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAJklEQVR4nO3NMQ0AAAwDoPo33arYsQQMkB6LQCAQCAQCgUAg+BIMi1X0pjxKe0gAAAAASUVORK5CYII=") : nil
                let messages = [AIMessage(role: .system, text: "Return only valid JSON: {\"result\":\"ok\"}."),
                                AIMessage(role: .user, text: "Confirm the connection by returning the requested JSON.", image: image)]
                let response = try await AIHTTPTransport().send(messages: messages,
                    config: connection.requestConfig(temperature: 0.1, maxTokens: 1024, deepThinking: deepThinking))
                guard !Task.isCancelled else { return }
                // Parse actual model output; HTTP success alone does not prove usable JSON output.
                let cleaned = response.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                guard let data = cleaned.data(using: .utf8),
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (json["result"] as? String)?.lowercased() == "ok" else {
                    throw AIServiceError.configuration("Connected, but the model did not return the expected result JSON.")
                }
                succeeded = true
                status = "Connection and result JSON verified."
            } catch {
                guard !Task.isCancelled else { return }
                succeeded = false
                status = error.localizedDescription
            }
        }
    }
}

private func adaptationRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
        Text(title.localized).font(.system(size: 13, design: .serif)).foregroundStyle(.secondary)
            .frame(width: 110, alignment: .leading)
        content()
        Spacer(minLength: 0)
    }
}
