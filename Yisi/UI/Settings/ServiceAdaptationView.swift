import SwiftUI

struct AIServiceConfigurationForm: View {
    let imageConfiguration: Bool
    @StateObject private var form: AIServiceFormModel
    @State private var task: Task<Void, Never>?

    init(imageConfiguration: Bool = false, form: AIServiceFormModel? = nil) {
        self.imageConfiguration = imageConfiguration
        _form = StateObject(wrappedValue: form ?? AIServiceFormModel(draft: AIServiceDraft.load(image: imageConfiguration)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                adaptationRow("Provider") {
                    CustomDropdown(selection: Binding(get: { form.draft.provider.rawValue }, set: { raw in
                        if let provider = APIProvider(rawValue: raw) {
                            form.draft = AIServiceDraft.load(image: imageConfiguration, provider: provider)
                            form.clearStatus()
                        }
                    }), options: providerOptions, displayNames: providerOptions.map { $0.localized })
                }
                if form.draft.provider == .custom {
                    adaptationRow("Protocol") {
                        CustomDropdown(selection: Binding(get: { form.draft.apiProtocol.rawValue }, set: { raw in
                            if let value = AIProtocol(rawValue: raw) {
                                form.draft.apiProtocol = value
                                form.draft.capabilities = ModelCapabilities()
                                form.draft.capabilities.supportsImages = imageConfiguration
                            }
                        }), options: AIProtocol.allCases.map(\.rawValue), displayNames: AIProtocol.allCases.map { $0.rawValue.localized })
                    }
                    APIKeyInput(label: "Base URL".localized, text: $form.draft.baseURL, placeholder: "https://example.com/v1", isSecure: false)
                }
                APIKeyInput(label: "API Key".localized, text: $form.draft.apiKey, placeholder: "Enter an API key.".localized)
                APIKeyInput(label: "Model".localized, text: $form.draft.model, placeholder: "Enter any model ID".localized, isSecure: false)
                Divider().opacity(0.2)
                adaptationRow("Deep Thinking Preference") { ElegantToggle(isOn: $form.draft.deepThinking) }
                CapabilityEditor(capabilities: $form.draft.capabilities, apiProtocol: form.draft.apiProtocol)
            }
            .disabled(form.testing)
            HStack(spacing: 10) {
                Button("Test and Save".localized, action: testAndSave)
                    .buttonStyle(.plain)
                    .foregroundColor(AppColors.primary)
                    .disabled(form.testing)
                if form.testing { ProgressView().controlSize(.small) }
            }
            .font(.system(size: 12))
            if !form.status.isEmpty {
                Text(form.status)
                    .font(.system(size: 11))
                    .foregroundColor(form.succeeded ? .secondary : .red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: form.draft.model) { _, model in
            if form.draft.provider != .custom {
                form.draft.capabilities = AIConfigurationStore.capabilities(provider: form.draft.provider, model: model,
                                                                        image: imageConfiguration)
                if imageConfiguration { form.draft.capabilities.supportsImages = true }
            }
            form.clearStatus()
        }
        .onChange(of: form.draft.apiKey) { _, _ in form.clearStatus() }
        .onChange(of: form.draft.baseURL) { _, _ in form.clearStatus() }
        .onChange(of: form.draft.capabilities) { _, _ in form.clearStatus() }
        .onChange(of: form.draft.deepThinking) { _, _ in form.clearStatus() }
        .onDisappear { task?.cancel() }
    }

    private var providerOptions: [String] {
        ["Gemini", "OpenAI", "Zhipu AI", "MiniMax", "DeepSeek", "Custom Service"]
    }

    private func testAndSave() {
        guard !form.testing else { return }
        task = Task { @MainActor in
            _ = await form.testAndSave()
        }
    }
}

struct CapabilityEditor: View {
    @Binding var capabilities: ModelCapabilities
    let apiProtocol: AIProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

private func adaptationRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack {
        Text(title.localized).font(.system(size: 13, design: .serif)).foregroundStyle(.secondary)
            .frame(width: 80, alignment: .leading)
        content()
        Spacer(minLength: 0)
    }
}
