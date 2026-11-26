import SwiftUI

struct AIServiceConfigurationForm: View {
    let imageConfiguration: Bool
    /// Onboarding configures a built-in service only; provider modules appear in Settings.
    private let offersModules: Bool
    @StateObject private var form: AIServiceFormModel
    @ObservedObject private var modules = ModuleStore.shared
    /// The provider module being shown instead of a built-in service, if any.
    @State private var moduleID: String?
    @State private var task: Task<Void, Never>?

    init(imageConfiguration: Bool = false, form: AIServiceFormModel? = nil) {
        self.imageConfiguration = imageConfiguration
        self.offersModules = form == nil
        _form = StateObject(wrappedValue: form ?? AIServiceFormModel(draft: AIServiceDraft.load(image: imageConfiguration)))
        let key = imageConfiguration ? "image_api_provider" : "api_provider"
        let selected = UserDefaults.standard.string(forKey: key) ?? ""
        _moduleID = State(initialValue: form == nil && selected.hasPrefix(AIConfigurationStore.modulePrefix)
            ? String(selected.dropFirst(AIConfigurationStore.modulePrefix.count)) : nil)
    }

    private var providerModules: [Module] { offersModules ? modules.modules(for: .provider) : [] }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
            adaptationRow("Provider") {
                CustomDropdown(selection: Binding(get: {
                    moduleID.map { AIConfigurationStore.modulePrefix + $0 } ?? form.draft.provider.rawValue
                }, set: { raw in
                    if raw.hasPrefix(AIConfigurationStore.modulePrefix) {
                        moduleID = String(raw.dropFirst(AIConfigurationStore.modulePrefix.count))
                    } else if let provider = APIProvider(rawValue: raw) {
                        moduleID = nil
                        form.draft = AIServiceDraft.load(image: imageConfiguration, provider: provider)
                    }
                    form.clearStatus()
                }), options: providerOptions + providerModules.map { AIConfigurationStore.modulePrefix + $0.id },
                   displayNames: providerOptions.map { $0.localized } + providerModules.map(\.name))
            }
            if let moduleID {
                ProviderModulePanel(moduleID: moduleID, imageConfiguration: imageConfiguration)
            } else {
                serviceForm
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

    @ViewBuilder
    private var serviceForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
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
                TestResult(text: form.status, succeeded: form.succeeded, dismiss: form.clearStatus)
            }
            .font(.yisi(12))
        }
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
                VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
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
                            .font(.yisi(11)).foregroundStyle(.secondary)
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
            .font(.yisi(12))
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
    SettingsRow(title: title.localized, control: content)
}

/// An AI service module chosen as the provider: "Test and Use", which only switches after a
/// successful answer, the same promise the built-in form makes. Managing it happens under Modules.
private struct ProviderModulePanel: View {
    let moduleID: String
    let imageConfiguration: Bool
    @ObservedObject private var store = ModuleStore.shared
    @State private var testing = false
    @State private var status = ""
    @State private var succeeded = false

    private var key: String { imageConfiguration ? "image_api_provider" : "api_provider" }
    private var inUse: Bool { UserDefaults.standard.string(forKey: key) == AIConfigurationStore.modulePrefix + moduleID }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let module = store.module(moduleID) {
                let moduleStatus = ModuleStatus(module, store: store)
                Text(module.manifest.description ?? module.meta)
                    .font(.yisi(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if moduleStatus == .ready {
                        Button((inUse ? "Test Again" : "Test and Use").localized) { test(module) }
                            .buttonStyle(.plain)
                            .foregroundColor(AppColors.primary)
                            .disabled(testing)
                    } else {
                        Text(moduleStatus.label).foregroundColor(moduleStatus.color)
                    }
                    if testing { ProgressView().controlSize(.small) }
                    TestResult(text: status, succeeded: succeeded) { status = "" }
                    Spacer()
                    ManageInModulesLink(role: .provider)
                }
                .font(.yisi(12))
            } else {
                Text(ModuleError.notFound(moduleID).localizedDescription)
                    .font(.yisi(12))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func test(_ module: Module) {
        testing = true
        status = ""
        Task { @MainActor in
            defer { testing = false }
            do {
                _ = try await store.text(module.id, ModuleRequest(text: "Reply with OK to confirm the connection."))
                UserDefaults.standard.set(AIConfigurationStore.modulePrefix + module.id, forKey: key)
                UserDefaults.standard.set("ai", forKey: AppDefaults.Keys.translationEngine)
                succeeded = true
                status = "Connection successful. Settings saved.".localized
            } catch {
                succeeded = false
                status = "Test failed. Previous settings were kept.".localized + " " + error.localizedDescription
            }
        }
    }
}

/// A test's outcome on one line beside its button. It fades away on its own; a failure stays a moment
/// longer so its reason can be read, and the full text is in the tooltip if it is cut short.
private struct TestResult: View {
    let text: String
    let succeeded: Bool
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            if !text.isEmpty {
                Text(text)
                    .font(.yisi(11))
                    .foregroundColor(succeeded ? .secondary : .red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(text)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: text)
        .task(id: text) {
            guard !text.isEmpty else { return }
            try? await Task.sleep(for: .seconds(succeeded ? 1.5 : 4))
            if !Task.isCancelled { dismiss() }
        }
    }
}
