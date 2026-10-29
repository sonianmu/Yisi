import SwiftUI
import UniformTypeIdentifiers

struct TranslationSourcesSettingsView: View {
    @ObservedObject private var store: TranslationSourceStore
    @AppStorage(TranslationSourceStore.selectedKey) private var selectedID = ""
    @State private var secret = ""
    @State private var status = ""
    @State private var testing = false
    @State private var hasSavedSecret = false
    @State private var showManagement = false
    @State private var managementWidth: CGFloat = 110

    init(store: TranslationSourceStore = .shared, defaults: UserDefaults = .standard) {
        _store = ObservedObject(wrappedValue: store)
        _selectedID = AppStorage(wrappedValue: "", TranslationSourceStore.selectedKey, store: defaults)
    }

    private var selected: TranslationSource? { store.sources.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionHeader(title: "Translation Sources".localized)
                Spacer()
                HStack(spacing: 8) {
                    Button(action: importConfiguration) {
                        Text("Import Configuration".localized)
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(AppColors.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        showManagement.toggle()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(showManagement ? AppColors.primary : Color.secondary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Manage Translation Sources".localized)
                    .accessibilityValue((showManagement ? "Expanded" : "Collapsed").localized)
                }
                .fixedSize()
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { managementWidth = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, width in managementWidth = width }
                    }
                }
            }

            if store.sources.isEmpty {
                Text("No Sources Added".localized)
                    .foregroundStyle(.secondary.opacity(0.7))
            } else {
                CustomDropdown(selection: $selectedID, options: store.sources.map(\.id), displayNames: store.sources.map(\.name))
                if let selected {
                    HStack {
                        Text(selected.destination).foregroundStyle(.secondary).textSelection(.enabled)
                        Spacer()
                        Button((store.isApproved(selected) ? "Approved Source" : "Review Source").localized) {
                            if store.isApproved(selected) { store.revoke(selected) }
                            else { review(selected) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.primary)
                        .help("Click an approved source to revoke access.".localized)
                    }
                    if selected.requiresSecret {
                        HStack(spacing: 12) {
                            SecureField((hasSavedSecret ? "API key saved in Keychain" : "API Key").localized, text: $secret)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            Button("Save".localized) {
                                do {
                                    try store.saveSecret(secret, for: selected)
                                    secret = ""
                                    hasSavedSecret = true
                                    status = "API key saved in Keychain".localized
                                } catch { status = error.localizedDescription }
                            }
                            .disabled(secret.isEmpty)
                            if hasSavedSecret {
                                Button("Delete Key".localized) {
                                    store.deleteSecret(for: selected)
                                    hasSavedSecret = false
                                    status = ""
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Text("Translation and local OCR only".localized).foregroundStyle(.secondary)
                        Spacer()
                        Button((testing ? "Testing Source..." : "Test Source").localized) {
                            testing = true
                            status = ""
                            let testedID = selectedID
                            Task {
                                let result: String
                                do { result = try await store.translate("Hello", source: "en", target: "zh-Hans") }
                                catch { result = error.localizedDescription }
                                if selectedID == testedID { status = result }
                                testing = false
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.primary)
                        .disabled(testing || !store.isApproved(selected))
                    }
                }
            }
            if !status.isEmpty {
                Text(status).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if !store.loadErrors.isEmpty {
                DisclosureGroup("Source Configuration Errors".localized) {
                    Text(store.loadErrors.joined(separator: "\n")).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .font(.system(size: 12, design: .serif))
        .frame(minHeight: showManagement ? 140 : nil, alignment: .top)
        .overlay {
            if showManagement {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { showManagement = false }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showManagement {
                VStack(alignment: .leading, spacing: 2) {
                    managementAction("Configuration Guide", action: openGuide)
                    managementAction("Sources Folder", action: openDirectory)
                    managementAction("Reload Sources", action: reload)
                }
                .padding(6)
                .frame(width: managementWidth)
                .background(GlassBackground(isFloating: true, cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                .offset(y: 32)
            }
        }
        .onExitCommand { showManagement = false }
        .onDisappear { showManagement = false }
        .onAppear { reload(); refreshSecretState() }
        .onChange(of: selectedID) { _, _ in secret = ""; status = ""; refreshSecretState() }
    }

    private func refreshSecretState() {
        hasSavedSecret = selected.map { $0.requiresSecret && store.hasSecret(for: $0) } ?? false
    }

    private func managementAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            showManagement = false
            action()
        } label: {
            Text(title.localized)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openGuide() {
        if let resources = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resources.appendingPathComponent("TranslationSources/translation-sources.md").path) {
            NSWorkspace.shared.open(resources.appendingPathComponent("TranslationSources/translation-sources.md"))
        } else if let url = URL(string: "https://github.com/sonianmu/Yisi/blob/main/docs/translation-sources.md") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reload() {
        store.reload()
        if !store.sources.contains(where: { $0.id == selectedID }) { selectedID = store.sources.first?.id ?? "" }
    }

    private func review(_ source: TranslationSource) {
        let alert = AppAlert()
        alert.messageText = "Allow this translation source?".localized
        alert.informativeText = String(format: "Selected text and OCR text will be sent to %@. Only approve sources you trust. Configuration changes require approval again.".localized, source.endpoint)
        alert.addButton(withTitle: "Allow Source".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.defaultButtonIndex = 1
        if alert.runModal() == .alertFirstButtonReturn { store.approve(source) }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let source = try TranslationSourceStore.read(url)
            if store.sources.contains(where: { $0.id == source.id }) {
                let alert = AppAlert()
                alert.messageText = "Replace source configuration?".localized
                alert.informativeText = source.name
                alert.addButton(withTitle: "Replace".localized)
                alert.addButton(withTitle: "Cancel".localized)
                alert.defaultButtonIndex = 1
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            try store.install(source)
            selectedID = source.id
            secret = ""
            status = ""
            refreshSecretState()
            review(source)
        } catch { status = error.localizedDescription }
    }

    private func openDirectory() {
        store.reload()
        NSWorkspace.shared.open(store.directory)
    }
}
