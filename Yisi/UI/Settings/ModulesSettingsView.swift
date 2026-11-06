import SwiftUI
import AppKit

// MARK: - Presentation

extension ModuleRole {
    /// Tab order on the Modules page.
    static let tabs: [ModuleRole] = [.provider, .preset, .translator]

    var title: String {
        switch self {
        case .provider: return "AI Services".localized
        case .preset: return "Presets".localized
        case .translator: return "Translation Sources".localized
        }
    }

    /// What this kind of module is for, shown while the tab is empty.
    var summary: String {
        switch self {
        case .provider: return "Powers Yisi's translation. Choose it under AI Service.".localized
        case .preset: return "Works on the selected text or screenshot. Choose it under Modes.".localized
        case .translator: return "Replaces the translation engine. Choose it under Translation → Other Sources.".localized
        }
    }
}

extension Module {
    var kind: String {
        switch manifest.handler {
        case .prompt: return "Prompt".localized
        case .http: return "Service".localized
        case .command: return "Program".localized
        }
    }

    /// "Program · ⌃⌥R" — what the module is, at a glance.
    var meta: String {
        var parts = [kind]
        if case .http(let handler) = manifest.handler { parts.append(handler.destination) }
        if role == .preset, let combo = PresetShortcuts.combo(for: selection, fallback: manifest.shortcut) {
            parts.append(combo.displayString)
        }
        return parts.joined(separator: " · ")
    }
}

enum ModuleStatus: Equatable {
    case ready, needsApproval, needsKey(String), shortcut(String)

    @MainActor init(_ module: Module, store: ModuleStore? = nil) {
        switch (store ?? .shared).readiness(of: module) {
        case .approvalRequired?: self = .needsApproval
        case .missingSecret(let name)?: self = .needsKey(name)
        default:
            if let issue = GlobalShortcutManager.shared.presetShortcutIssues[module.selection] { self = .shortcut(issue) }
            else { self = .ready }
        }
    }

    var label: String {
        switch self {
        case .ready: return "Ready".localized
        case .needsApproval: return "Needs approval".localized
        case .needsKey: return "Needs key".localized
        case .shortcut: return "Shortcut conflict".localized
        }
    }

    var color: Color {
        switch self {
        case .ready: return .secondary.opacity(0.7)
        case .needsApproval: return AppColors.primary
        case .needsKey, .shortcut: return .orange
        }
    }
}

/// A quiet text action in the accent color, used for secondary actions across module settings.
struct QuietButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(AppColors.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A row-level action written as a link, like Repair Software beside it.
struct TextAction: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(AppColors.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Navigation

extension Notification.Name {
    /// Opens Settings → Modules on the tab stored under `ModulesPage.tabKey`.
    static let showModules = Notification.Name("ShowModules")
}

enum ModulesPage {
    static let tabKey = "settings_modules_tab"

    @MainActor static func show(_ role: ModuleRole) {
        UserDefaults.standard.set(role.rawValue, forKey: tabKey)
        NotificationCenter.default.post(name: .showModules, object: nil)
    }
}

/// The one link other pages show: modules are chosen there, managed here.
struct ManageInModulesLink: View {
    let role: ModuleRole
    var title = "Manage in Modules"

    var body: some View {
        Button { ModulesPage.show(role) } label: {
            Text(title.localized)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(AppColors.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Agent handoff

enum AgentHandoff {
    /// The sentence a user pastes to their agent. Everything else is in that kind's AGENTS.md.
    static func instructions(for role: ModuleRole) -> String {
        let home = YisiHome.shared
        let binary = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Yisi").path
            : "/Applications/Yisi.app/Contents/MacOS/Yisi"
        let format: String
        switch role {
        case .provider: format = "Read %@ and build a Yisi AI service for me: [describe the model, API or agent]. Write it into %@, then check it with \"%@\" modules validate."
        case .preset: format = "Read %@ and build a Yisi preset for me: [describe what it should do with the selected text or screenshot]. Write it into %@, then check it with \"%@\" modules validate."
        case .translator: format = "Read %@ and build a Yisi translation source for me: [describe the service or agent]. Write it into %@, then check it with \"%@\" modules validate."
        }
        return String(format: format.localized, home.guide(for: role).path, home.folder(for: role).path, binary)
    }

    static func copy(_ role: ModuleRole) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(instructions(for: role), forType: .string)
    }

    static func openGuide(_ role: ModuleRole) {
        try? YisiHome.shared.prepare()
        NSWorkspace.shared.open(YisiHome.shared.guide(for: role))
    }

    static func openFolder(_ role: ModuleRole) {
        try? YisiHome.shared.prepare()
        NSWorkspace.shared.open(YisiHome.shared.folder(for: role))
    }
}

/// "Copy Instructions for Your Agent", which confirms itself for a moment.
struct AgentHandoffButton: View {
    let role: ModuleRole
    @State private var copied = false

    var body: some View {
        TextAction(title: (copied ? "Copied" : "Copy Instructions for Your Agent").localized) {
            AgentHandoff.copy(role)
            withAnimation(.easeOut(duration: 0.2)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.2)) { copied = false }
            }
        }
    }
}

// MARK: - Modules page

/// The one place modules are managed. Yisi supplies the page, the permissions and the popup;
/// what a module does is up to the user's agent.
struct ModulesSettingsView: View {
    @ObservedObject private var store = ModuleStore.shared
    @ObservedObject private var shortcuts = GlobalShortcutManager.shared
    @AppStorage(ModulesPage.tabKey) private var tab = ModuleRole.provider.rawValue
    @Environment(\.settingsPageHeight) private var pageHeight
    @State private var inspecting: Module?

    private var role: ModuleRole { ModuleRole(rawValue: tab) ?? .provider }

    private var actions: some View {
        HStack(spacing: 16) {
            AgentHandoffButton(role: role)
            TextAction(title: "Open Folder".localized) { AgentHandoff.openFolder(role) }
            TextAction(title: "Guide".localized) { AgentHandoff.openGuide(role) }
        }
    }

    var body: some View {
        let modules = store.modules(for: role)
        let issues = store.issues.filter { $0.role == role || $0.role == nil }
        let empty = modules.isEmpty && issues.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Modules".localized)
            ElegantSegmentedPicker(selection: $tab, options: ModuleRole.tabs.map { ($0.rawValue, $0.title) })
                .padding(.bottom, 4)

            if !modules.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(modules) { module in
                        ModuleRow(module: module, status: ModuleStatus(module, store: store)) { inspecting = module }
                    }
                }
            }
            if !issues.isEmpty { IssueList(issues: issues) }
            if !empty { actions.padding(.top, 4) }
        }
        // An empty tab centres its one line on the whole pane, not on the space under the tabs.
        .frame(maxWidth: .infinity, minHeight: empty ? pageHeight : nil, alignment: .topLeading)
        .overlay {
            if empty {
                VStack(spacing: 14) {
                    Text(role.summary)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    actions
                }
            }
        }
        .onAppear { store.reload() }
        .sheet(item: $inspecting) { module in
            ModuleDetailView(module: module) { inspecting = nil }
        }
    }
}

/// Folders that did not load, with the reason, so the user can hand it back to their agent.
struct IssueList: View {
    let issues: [ModuleIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Could Not Load".localized)
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(.secondary)
            ForEach(issues) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.folder).font(.system(size: 13, design: .serif))
                    Text(issue.message)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ModuleRow: View {
    let module: Module
    let status: ModuleStatus
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.name)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(.primary)
                    Text(module.manifest.description ?? module.meta)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(status.label)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(status.color)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(AppColors.primary.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, -8)
    }
}

// MARK: - Module detail

struct ModuleDetailView: View {
    let onClose: () -> Void
    @ObservedObject private var store = ModuleStore.shared
    @ObservedObject private var shortcuts = GlobalShortcutManager.shared
    @State private var module: Module
    @State private var secretDrafts: [String: String] = [:]
    @State private var sample: String
    @State private var result = ""
    @State private var failed = false
    @State private var running: Task<Void, Never>?

    init(module: Module, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _module = State(initialValue: module)
        _sample = State(initialValue: module.role == .provider ? "Reply with OK." : "Hello, world.")
    }

    private var status: ModuleStatus { ModuleStatus(module, store: store) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(module.name)
                    .font(.system(size: 20, weight: .medium, design: .serif))
                Text(module.meta)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.secondary)
                if let description = module.manifest.description {
                    Text(description)
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("What It Does") {
                let trust = module.trust
                if trust.actions.isEmpty {
                    line("Uses only its own folder and the AI service you chose.".localized)
                }
                ForEach(Array(trust.actions.enumerated()), id: \.offset) { _, action in
                    switch action {
                    case .sends(let endpoint): line(String(format: "Sends text to %@".localized, endpoint))
                    case .runs(let command): line(String(format: "Runs %@".localized, command))
                    case .reads(let path): line(String(format: "Reads %@".localized, path))
                    }
                }
                if module.manifest.acceptsImages {
                    line("Receives screenshots as images.".localized)
                }
                if case .shortcut(let issue) = status {
                    Text(issue).font(.system(size: 12, design: .serif)).foregroundStyle(.orange)
                }
            }

            let secrets = module.manifest.handler.secretNames
            if !secrets.isEmpty {
                section("Keys") {
                    ForEach(secrets, id: \.self) { name in secretRow(name) }
                    Text("Stored in Keychain. Never written to files or exported.".localized)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }

            section("Try It") {
                HStack(spacing: 8) {
                    TextField("", text: $sample)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .serif))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit(test)
                    QuietButton(title: (running == nil ? "Run" : "Stop").localized) {
                        if let running { running.cancel(); self.running = nil } else { test() }
                    }
                    .disabled(status == .needsApproval)
                }
                if !result.isEmpty {
                    ScrollView {
                        Text(result)
                            .font(.system(size: 13, design: .serif))
                            .foregroundStyle(failed ? Color.orange : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
            }

            HStack(spacing: 8) {
                QuietButton(title: "Show in Finder".localized) {
                    NSWorkspace.shared.activateFileViewerSelecting([module.manifestURL])
                }
                QuietButton(title: "Move to Trash".localized, action: remove)
                Spacer()
                if module.trust.needsApproval {
                    if store.isAllowed(module) {
                        QuietButton(title: "Revoke".localized) { store.revoke(module) }
                    } else {
                        DialogActionButton(title: "Allow".localized, primary: true) { store.allow(module) }
                            .frame(width: 88)
                    }
                }
                DialogActionButton(title: "Done".localized, primary: !module.trust.needsApproval || store.isAllowed(module), action: close)
                    .frame(width: 88)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .background(ThemeBackground())
        .onChange(of: store.modules) { _, modules in
            if let fresh = modules.first(where: { $0.id == module.id }) { module = fresh } else { close() }
        }
    }

    private func close() {
        running?.cancel()
        onClose()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title.localized)
            content()
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .serif))
            .foregroundStyle(.primary.opacity(0.85))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func secretRow(_ name: String) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
            if store.hasSecret(name, for: module) {
                Text("Saved".localized).font(.system(size: 12, design: .serif)).foregroundStyle(.secondary)
                Spacer()
                QuietButton(title: "Delete".localized) { store.deleteSecret(name, for: module) }
            } else {
                SecureField("Paste the key".localized, text: Binding(get: { secretDrafts[name] ?? "" },
                                                                    set: { secretDrafts[name] = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                QuietButton(title: "Save".localized) {
                    guard let value = secretDrafts[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
                    do {
                        try store.saveSecret(value, name: name, for: module)
                        secretDrafts[name] = nil
                    } catch {
                        result = error.localizedDescription
                        failed = true
                    }
                }
            }
        }
    }

    private func test() {
        guard running == nil else { return }
        result = ""
        failed = false
        let target = Language(rawValue: UserDefaults.standard.string(forKey: AppDefaults.Keys.defaultTargetLanguage) ?? "")?.code ?? "zh-Hans"
        let request = ModuleRequest(text: sample, target: target)
        let module = self.module
        running = Task { @MainActor in
            defer { running = nil }
            do {
                var output = ""
                for try await chunk in try store.run(module, request) {
                    output += chunk
                    result = output
                }
                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ModuleError.emptyResult }
            } catch is CancellationError {
            } catch {
                result = error.localizedDescription
                failed = true
            }
        }
    }

    private func remove() {
        do {
            if try ModuleRemoval.confirm(module) { close() }
        } catch {
            result = error.localizedDescription
            failed = true
        }
    }
}

enum ModuleRemoval {
    /// Asks, then moves the module folder to the Trash. Returns whether it was removed.
    @MainActor static func confirm(_ module: Module, store: ModuleStore? = nil) throws -> Bool {
        let alert = AppAlert()
        alert.messageText = String(format: "Move “%@” to the Trash?".localized, module.name)
        alert.informativeText = "Its folder goes to the Trash, so you can put it back from there. Its keys are deleted.".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash".localized)
        alert.addButton(withTitle: "Cancel".localized)
        alert.defaultButtonIndex = 1
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        try (store ?? .shared).remove(module)
        return true
    }
}

// MARK: - Translation source picker (Translation → Other Sources)

/// Choosing a translation source. Adding and managing them happens on the Modules page.
struct TranslatorPicker: View {
    @ObservedObject private var store = ModuleStore.shared
    @AppStorage(AppDefaults.Keys.externalTranslator) private var selectedID = ""

    var body: some View {
        let translators = store.modules(for: .translator)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Translation Sources".localized)
            if translators.isEmpty {
                HStack {
                    Text("No translation sources yet".localized)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(.secondary.opacity(0.7))
                    Spacer()
                    ManageInModulesLink(role: .translator, title: "Go to Modules")
                }
            } else {
                HStack(spacing: 12) {
                    CustomDropdown(selection: $selectedID, options: translators.map(\.id), displayNames: translators.map(\.name))
                    if let selected = translators.first(where: { $0.id == selectedID }) {
                        let status = ModuleStatus(selected, store: store)
                        if status != .ready {
                            Text(status.label).font(.system(size: 12, design: .serif)).foregroundStyle(status.color)
                        }
                    }
                    Spacer()
                    ManageInModulesLink(role: .translator)
                }
            }
        }
        .onAppear {
            store.reload()
            if !translators.contains(where: { $0.id == selectedID }) { selectedID = translators.first?.id ?? "" }
        }
    }
}

// MARK: - Data (General)

/// Export and import of everything the user owns. Lives in General, beside Repair.
struct DataSettingsSection: View {
    @State private var status = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Your Data".localized)
            HStack(spacing: 16) {
                TextAction(title: "Export".localized, action: export)
                TextAction(title: "Import".localized, action: importArchive)
                TextAction(title: "Show Folder".localized) {
                    try? YisiHome.shared.prepare()
                    NSWorkspace.shared.open(YisiHome.shared.root)
                }
                if working { ProgressView().controlSize(.small) }
            }
            .disabled(working)
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        panel.nameFieldStringValue = "Yisi Export \(stamp).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = true
        status = ""
        Task { @MainActor in
            defer { working = false }
            do {
                try DataArchive.export(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func importArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let summary = try DataArchive.stageImport(from: url)
            let alert = AppAlert()
            alert.messageText = "Import and restart Yisi?".localized
            alert.informativeText = String(format: "Adds %d modules and replaces history, learned rules and preferences.".localized, summary.modules)
            alert.addButton(withTitle: "Import and Restart".localized)
            alert.addButton(withTitle: "Cancel".localized)
            alert.defaultButtonIndex = 1
            if alert.runModal() == .alertFirstButtonReturn {
                AppRelauncher.relaunch()
            } else {
                try? FileManager.default.removeItem(at: YisiHome.shared.pendingImport)
            }
        } catch {
            status = error.localizedDescription
        }
    }
}
