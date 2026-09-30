import SwiftUI
import Translation
import ServiceManagement

enum ClosingMode: String, CaseIterable, Identifiable {
    case clickOutside = "clickOutside"
    case xButton = "xButton"
    case escKey = "escKey"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .clickOutside: return "Click Outside"
        case .xButton: return "X Button"
        case .escKey: return "Esc Key"
        }
    }
}

// MARK: - Translation Engine

enum TranslationEngine: String, CaseIterable {
    case system = "system"
    case ai = "ai"
    
    var displayName: String {
        switch self {
        case .system: return "macOS System"
        case .ai: return "AI Service"
        }
    }
}

// MARK: - Settings Navigation

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case aiService
    case modes
    case translation
    
    var id: String { rawValue }
}

struct SettingsView: View {
    @State private var selectedTopTab: Int = 0 // 0: History, 1: Settings
    @AppStorage(AppDefaults.Keys.appTheme) private var appTheme: String = AppDefaults.appTheme
    @ObservedObject private var localizationManager = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation
            HStack(spacing: 24) { // 減小標籤間距，更緊湊
                TopTabButton(title: "History".localized, isSelected: selectedTopTab == 0) { selectedTopTab = 0 }
                TopTabButton(title: "Settings".localized, isSelected: selectedTopTab == 1) { selectedTopTab = 1 }
                Spacer()
            }
            .padding(.leading, 20) // 微調對齊位置
            .padding(.trailing, 20)
            .padding(.top, 14)
            .padding(.bottom, 4) // 大幅減小，讓內容區上提
            
            // Content Area (使用 ZStack 保活視圖，避免切換時重新初始化)
            ZStack(alignment: .topLeading) {
                // History Tab (Index 0)
                HistoryView()
                    .opacity(selectedTopTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTopTab == 0) // 隱藏時禁止點擊
                
                // Settings Tab (Index 1)
                SettingsContent()
                    .opacity(selectedTopTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTopTab == 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // 填充剩餘空間
        }
        .frame(minWidth: 500, minHeight: 350)
        .background(ThemeBackground().edgesIgnoringSafeArea(.all))
        .preferredColorScheme(ColorScheme(from: appTheme))
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToHistory"))) { _ in
            selectedTopTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToSettings"))) { _ in
            selectedTopTab = 1
        }
    }
}

struct TopTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .medium : .regular, design: .serif))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                // Active Indicator
                Rectangle()
                    .fill(isSelected ? AppColors.primary.opacity(0.7) : Color.clear)
                    .frame(height: 1)
                    .frame(width: 20)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 截图快捷键录制器
struct ScreenshotShortcutRecorder: View {
    @State private var isRecording = false
    @State private var currentShortcut: String = ""
    @State private var monitor: Any?
    @State private var showHint = false

    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            HStack {
                if isRecording {
                    Text(showHint ? "Requires Cmd/Ctrl/Opt".localized : "Press keys...".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(showHint ? .orange : .accentColor)
                    Spacer()
                    Image(systemName: "record.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse)
                } else {
                    Text(currentShortcut.isEmpty ? "Record Shortcut".localized : currentShortcut)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.primary)
                    Spacer()
                    if !currentShortcut.isEmpty {
                        Button(action: {
                            resetShortcut()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(width: 160)
            .background(isRecording ? AppColors.primary.opacity(0.1) : AppColors.primary.opacity(0.05))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isRecording ? AppColors.primary.opacity(0.3) : AppColors.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            updateDisplay()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    
    private func resetShortcut() {
        GlobalShortcutManager.shared.updateScreenshotShortcut(keyCode: AppDefaults.screenshotShortcutKeyCode, modifiers: AppDefaults.screenshotShortcutMods)
        updateDisplay()
    }
    
    private func updateDisplay() {
        let keyCode = UserDefaults.standard.integer(forKey: AppDefaults.Keys.screenshotShortcutKey)
        let modifiers = UserDefaults.standard.integer(forKey: AppDefaults.Keys.screenshotShortcutModifiers)
        
        if keyCode != 0 {
            currentShortcut = shortcutString(keyCode: UInt16(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
        } else {
            currentShortcut = "⌘⇧X" // Default
        }
    }
    
    private func handleKeyDown(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        if event.type == .flagsChanged { return }
        if keyCode == 53 { stopRecording(); return }

        let hasPrimaryModifier = flags.contains(.command)
            || flags.contains(.control)
            || flags.contains(.option)
        guard hasPrimaryModifier else {
            showHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHint = false }
            return
        }

        GlobalShortcutManager.shared.updateScreenshotShortcut(keyCode: keyCode, modifiers: flags)
        updateDisplay()
        stopRecording()
    }
    
    private func shortcutString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var string = ""
        if modifiers.contains(.command) { string += "⌘" }
        if modifiers.contains(.control) { string += "⌃" }
        if modifiers.contains(.option) { string += "⌥" }
        if modifiers.contains(.shift) { string += "⇧" }
        
        switch keyCode {
        case 0: string += "A"; case 1: string += "S"; case 2: string += "D"; case 3: string += "F"
        case 4: string += "H"; case 5: string += "G"; case 6: string += "Z"; case 7: string += "X"
        case 8: string += "C"; case 9: string += "V"; case 11: string += "B"; case 12: string += "Q"
        case 13: string += "W"; case 14: string += "E"; case 15: string += "R"; case 16: string += "Y"
        case 17: string += "T"; case 31: string += "O"; case 32: string += "U"; case 34: string += "I"
        case 35: string += "P"; case 37: string += "L"; case 38: string += "J"; case 40: string += "K"
        case 45: string += "N"; case 46: string += "M"
        default: string += "?"
        }
        return string
    }
}

struct SettingsContent: View {
    @State private var selectedSection: String = "General"
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @Environment(\.colorScheme) var currentColorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar (Original Design)
            VStack(alignment: .leading, spacing: 4) {
                SidebarButton(title: "General".localized, isSelected: selectedSection == "General") { selectedSection = "General" }
                SidebarButton(title: "AI Service".localized, isSelected: selectedSection == "AI Service") { selectedSection = "AI Service" }
                SidebarButton(title: "Modes".localized, isSelected: selectedSection == "Modes") { selectedSection = "Modes" }
                SidebarButton(title: "Translation".localized, isSelected: selectedSection == "Translation") { selectedSection = "Translation" }
                
                Spacer()
                
                // About Section (Bottom)
                SidebarButton(title: "About".localized, isSelected: selectedSection == "About") { selectedSection = "About" }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(width: 120)
            .background(
                Group {
                    if currentColorScheme == .dark {
                        ZStack {
                            Color(hex: "29292C")
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        }
                    } else {
                        ZStack {
                            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                            Color.white.opacity(0.1)
                        }
                    }
                }
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(currentColorScheme == .dark ? 0.5 : 0.1), radius: 10, x: 0, y: 0)
            )
            .padding(.leading, 8)
            .padding(.top, 8)
            .padding(.bottom, 8)
            
            // Section Content
            TransparentScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedSection {
                    case "AI Service":
                        AIServiceSettingsView()
                    case "Modes":
                        ModesSettingsView()
                    case "Translation":
                        TranslationSettingsView()
                    case "About":
                        AboutView()
                    default:
                        GeneralSettingsView()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SidebarButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular, design: .serif))
                .foregroundColor(isSelected ? AppColors.primary : AppColors.text.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AppColors.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Elegant Segmented Picker (Sliding Capsule)

struct ElegantSegmentedPicker: View {
    @Binding var selection: String
    let options: [(tag: String, label: String)]

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.tag) { option in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = option.tag
                    }
                }) {
                    Text(option.label)
                        .font(.system(size: 13, weight: selection == option.tag ? .medium : .regular, design: .serif))
                        .foregroundColor(selection == option.tag ? AppColors.primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            Group {
                                if selection == option.tag {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(AppColors.primary.opacity(0.1))
                                        .matchedGeometryEffect(id: "indicator", in: namespace)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.primary.opacity(0.04))
        )
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @AppStorage(AppDefaults.Keys.closeMode) private var closeMode: String = AppDefaults.closeMode
    @AppStorage(AppDefaults.Keys.appTheme) private var appTheme: String = AppDefaults.appTheme
    @AppStorage(AppDefaults.Keys.autoCheckUpdates) private var autoCheckUpdates: Bool = AppDefaults.autoCheckUpdates
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Language & Appearance
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Language".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    CustomDropdown(
                        selection: $localizationManager.language,
                        options: ["en", "zh"],
                        displayNames: ["English".localized, "Simplified Chinese".localized]
                    )
                }
                
                HStack {
                    Text("Appearance".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    CustomDropdown(
                        selection: $appTheme,
                        options: ["light", "dark"],
                        displayNames: ["Light".localized, "Dark".localized]
                    )
                }
                .onAppear {
                    if appTheme == "system" {
                        appTheme = "light"
                    }
                }
            }
            
            Divider().opacity(0.3)
            
            // Window Behavior
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Behavior".localized)
                
                HStack {
                    Text("Auto Start".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    ElegantToggle(isOn: $launchAtLogin)
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

                HStack {
                    Text("Auto Update".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)

                    ElegantToggle(isOn: $autoCheckUpdates)

                    Spacer()

                    Button(action: {
                        UpdateManager.shared.checkForUpdates(silent: false)
                    }) {
                        Text("Check for Updates".localized)
                            .font(.system(size: 12, design: .serif))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                
                HStack {
                    Text("Close Mode".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    CustomDropdown(selection: $closeMode, options: ClosingMode.allCases.map { $0.rawValue }, displayNames: ClosingMode.allCases.map { $0.displayName.localized })
                }
                
                Divider().opacity(0.2)
                
                HStack {
                    Text("Layout".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    Button(action: {
                        LayoutEditorManager.shared.openEditor()
                    }) {
                        Text("Customize Popup Layout".localized)
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider().opacity(0.3)
            
            // Shortcuts
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Shortcuts".localized)
                
                HStack {
                    Text("Activate".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    ShortcutRecorder()
                }
                
                HStack {
                    Text("Screenshot".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    ScreenshotShortcutRecorder()
                }
                
                Text("Press the key combination you want to use.".localized)
                    .font(.system(size: 12, design: .serif))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 4)
            }
            Divider().opacity(0.3)
            SoftwareRepairSection()
        }
    }
}

// MARK: - AI Service Settings View

struct AIServiceSettingsView: View {
    @AppStorage(AppDefaults.Keys.imageProcessingStrategy) private var imageStrategy = AppDefaults.imageProcessingStrategy
    @AppStorage(AppDefaults.Keys.applyApiToImageMode) private var sameAPI = AppDefaults.applyApiToImageMode
    @State private var supportsImages = AIConfigurationStore.resolve().capabilities.supportsImages

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            AIServiceConfigurationForm()
            Divider().opacity(0.3)
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Image Mode".localized)
                ElegantSegmentedPicker(selection: $imageStrategy,
                    options: [("local_ocr", "System OCR".localized), ("ai_vision", "AI Vision".localized)])
                if imageStrategy == "local_ocr" {
                    Text("Only recognizes pure text structures in images".localized)
                        .font(.system(size: 12)).foregroundColor(.secondary)
                } else {
                    HStack {
                        Text("Same API".localized).font(.system(size: 13, design: .serif))
                            .foregroundColor(.secondary).frame(width: 80, alignment: .leading)
                        ElegantToggle(isOn: $sameAPI).disabled(!supportsImages)
                        Text(supportsImages ? "Apply text settings to image mode".localized : "This model is not configured for image input".localized)
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    if !sameAPI { AIServiceConfigurationForm(imageConfiguration: true) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            supportsImages = AIConfigurationStore.resolve().capabilities.supportsImages
            if !supportsImages && sameAPI { sameAPI = false }
        }
    }
}

// MARK: - Modes Settings View (Renamed from PromptsSection)

struct ModesSettingsView: View {
    @AppStorage(AppDefaults.Keys.presetModeEnabled) private var presetModeEnabled: Bool = AppDefaults.presetModeEnabled
    @AppStorage(AppDefaults.Keys.selectedPresetId) private var selectedPresetId: String = AppDefaults.selectedPresetId
    @State private var presets: [PromptPreset] = []
    @State private var editingPreset: PromptPreset?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preset Mode Toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Preset Mode".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.primary)
                    Text("Use saved presets instead of custom mode".localized)
                        .font(.system(size: 11, design: .serif))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
                ElegantToggle(isOn: $presetModeEnabled)
            }
            
            Divider().opacity(0.3)
            
            // Preset Selection (Only visible when preset mode is enabled)
            if presetModeEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Preset".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.primary)
                    
                    // Default Translation Preset (Built-in)
                    PresetRadioRow(
                        id: AppDefaults.selectedPresetId,
                        name: "Default Translation".localized,
                        description: "",
                        isSelected: selectedPresetId == AppDefaults.selectedPresetId,
                        onSelect: { selectedPresetId = AppDefaults.selectedPresetId }
                    )
                    
                    Divider().opacity(0.3)
                    
                    // User Presets Header
                    HStack {
                        Text("Custom Presets".localized)
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            editingPreset = PromptPreset(id: UUID(), name: "", inputPerception: "", outputInstruction: "")
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(5)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // User Presets List
                    if presets.isEmpty {
                        Text("No custom presets yet".localized)
                            .font(.system(size: 12, design: .serif))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(presets) { preset in
                                PresetRadioRow(
                                    id: preset.id.uuidString,
                                    name: preset.name,
                                    description: "\(preset.inputPerception.prefix(30))...",
                                    isSelected: selectedPresetId == preset.id.uuidString,
                                    onSelect: { selectedPresetId = preset.id.uuidString },
                                    onEdit: {
                                        editingPreset = preset
                                    },
                                    onDelete: { deletePreset(preset) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadPresets() }
        .sheet(item: $editingPreset) { preset in
            let isNew = !presets.contains(where: { $0.id == preset.id })
            PresetEditor(preset: preset, isNew: isNew, onSave: { updated in
                if isNew {
                    addPreset(updated)
                } else {
                    updatePreset(updated)
                }
                editingPreset = nil
            }, onCancel: {
                editingPreset = nil
            })
        }
    }
    
    private func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: AppDefaults.Keys.savedPresets),
           let decoded = try? JSONDecoder().decode([PromptPreset].self, from: data) {
            presets = decoded
        }
    }
    
    private func addPreset(_ preset: PromptPreset) {
        presets.append(preset)
        persistPresets()
    }
    
    private func updatePreset(_ preset: PromptPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
            persistPresets()
        }
    }
    
    private func deletePreset(_ preset: PromptPreset) {
        presets.removeAll { $0.id == preset.id }
        // Reset to default translation if deleting currently selected preset
        if selectedPresetId == preset.id.uuidString {
            selectedPresetId = AppDefaults.selectedPresetId
        }
        persistPresets()
    }
    
    private func persistPresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: AppDefaults.Keys.savedPresets)
        }
    }
}

// MARK: - Translation Settings View

struct TranslationSettingsView: View {
    @AppStorage(AppDefaults.Keys.translationEngine) private var translationEngine: String = AppDefaults.translationEngine
    @AppStorage(AppDefaults.Keys.defaultSourceLanguage) private var defaultSourceLanguage: String = AppDefaults.defaultSourceLanguage
    @AppStorage(AppDefaults.Keys.defaultTargetLanguage) private var defaultTargetLanguage: String = AppDefaults.defaultTargetLanguage
    @AppStorage(AppDefaults.Keys.enableImproveFeature) private var enableImproveFeature: Bool = AppDefaults.enableImproveFeature
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Default Translation Path (moved first)
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Default Path".localized)
                
                HStack {
                    Text("Source".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    CustomDropdown(
                        selection: $defaultSourceLanguage,
                        options: Language.sourceLanguages.map { $0.rawValue },
                        displayNames: Language.sourceLanguages.map { $0.displayName }
                    )
                }
                
                HStack {
                    Text("Target".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    
                    CustomDropdown(
                        selection: $defaultTargetLanguage,
                        options: Language.targetLanguages.map { $0.rawValue },
                        displayNames: Language.targetLanguages.map { $0.displayName }
                    )
                }
            }
            
            Divider().opacity(0.3)
            
            // Engine Selector (moved second, custom style)
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Engine".localized)
                
                HStack(spacing: 0) {
                    ElegantSegmentedPicker(
                        selection: $translationEngine,
                        options: [("system", "System Translation".localized), ("ai", "AI Translation".localized)]
                    )
                }
            }
            
            // AI-specific settings
            if translationEngine == "ai" {
                Divider().opacity(0.3)
                
                // Smart Improve Toggle
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Smart Improve".localized)
                    
                    HStack {
                        ElegantToggle(isOn: $enableImproveFeature)
                        
                        Text("Learn from your corrections".localized)
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    Text("Text mode only. Images excluded to save space.".localized)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                
                Divider().opacity(0.3)
                
                // Learned Rules Section
                LearnedRulesSection()
            } else {
                Divider().opacity(0.3)
                
                if #available(macOS 15.0, *) {
                    LanguagePackStatusView(
                        defaultSource: defaultSourceLanguage,
                        defaultTarget: defaultTargetLanguage
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "System Translation".localized)
                        Text("Requires macOS 15.0 or later.".localized)
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Language Pack Status View

@available(macOS 15.0, *)
private struct LanguagePackStatusView: View {
    let defaultSource: String
    let defaultTarget: String
    
    @ObservedObject private var translationManager = SystemTranslationManager.shared
    @State private var languageStatuses: [(code: String, name: String, installed: Bool)] = []
    @State private var isLoading = true
    
    private static let displayOrder: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("ru", "Русский"),
        ("ar", "العربية"),
        ("th", "ไทย"),
        ("vi", "Tiếng Việt")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "System Translation".localized)
            
            Text("macOS built-in translation. Fast, private, requires language pack.".localized)
                .font(.system(size: 12, design: .serif))
                .foregroundColor(.secondary.opacity(0.7))
            
            Divider().opacity(0.2)
            
            SectionHeader(title: "Language Packs".localized)
            
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                    // ... (rest of view)
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                    Text("Checking...".localized)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(languageStatuses.enumerated()), id: \.offset) { index, lang in
                        LanguagePackRow(
                            name: lang.name,
                            installed: lang.installed,
                            onDownload: {
                                let refLang = lang.code.hasPrefix("en") ? "zh-Hans" : "en"
                                translationManager.requestDownload(
                                    source: lang.code,
                                    target: refLang
                                )
                            }
                        )
                        
                        if index < languageStatuses.count - 1 {
                            Divider().opacity(0.08).padding(.leading, 8)
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(AppColors.primary.opacity(0.03))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppColors.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
        }
        .onAppear { Task { await refreshStatuses() } }
        .translationTask(translationManager.downloadConfiguration) { session in
            try? await session.prepareTranslation()
            await refreshStatuses()
        }
    }
    
    private func refreshStatuses() async {
        isLoading = true
        let availability = LanguageAvailability()
        var results: [(code: String, name: String, installed: Bool)] = []
        
        for lang in Self.displayOrder {
            let refLang = lang.code.hasPrefix("en") ? "zh-Hans" : "en"
            let status = await availability.status(
                from: Locale.Language(identifier: lang.code),
                to: Locale.Language(identifier: refLang)
            )
            if status != LanguageAvailability.Status.unsupported {
                results.append((code: lang.code, name: lang.name, installed: status == LanguageAvailability.Status.installed))
            }
        }
        
        // installed first, then not-installed
        results.sort { lhs, rhs in
            if lhs.installed && !rhs.installed { return true }
            if !lhs.installed && rhs.installed { return false }
            return false
        }
        
        languageStatuses = results
        isLoading = false
    }
}

@available(macOS 15.0, *)
private struct LanguagePackRow: View {
    let name: String
    let installed: Bool
    let onDownload: () -> Void
    
    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13, design: .serif))
                .foregroundColor(.primary)
            
            Spacer()
            
            if installed {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppColors.primary.opacity(0.5))
            } else {
                Button(action: onDownload) {
                    Text("Download".localized)
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundColor(AppColors.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.primary.opacity(0.08))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(AppColors.primary.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Legacy Section (kept for compatibility, will be removed)

struct GeneralSection: View {
    var body: some View {
        GeneralSettingsView()
    }
}

class LayoutEditorManager {
    static let shared = LayoutEditorManager()
    var editorWindow: NSWindow?
    
    func openEditor() {
        editorWindow?.close()
        
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.frame
        
        // Load existing frame or default
        var initialFrame = CGRect(x: screenRect.midX - 200, y: screenRect.midY - 150, width: 400, height: 300)
        
        if let savedData = UserDefaults.standard.data(forKey: AppDefaults.Keys.popupFrameRect),
           let savedRect = try? JSONDecoder().decode(CGRect.self, from: savedData) {
            // Convert Cocoa (Bottom-Left) to SwiftUI (Top-Left)
            // Cocoa Y is from bottom. SwiftUI Y is from top.
            // swiftUI_Y = screenHeight - (cocoaY + height)
            let swiftUI_Y = screenRect.height - (savedRect.origin.y + savedRect.height)
            initialFrame = CGRect(x: savedRect.origin.x, y: swiftUI_Y, width: savedRect.width, height: savedRect.height)
        } else {
             // Default center (SwiftUI coords)
             // screenRect.midY is center.
             // Top-Left Y = center Y - height/2? No.
             // SwiftUI (0,0) is top-left.
             // Center Y in SwiftUI is screenHeight / 2.
             // So y = screenHeight/2 - 150.
             initialFrame = CGRect(x: screenRect.width/2 - 200, y: screenRect.height/2 - 150, width: 400, height: 300)
        }
        
        let contentView = LayoutEditorView(
            initialFrame: initialFrame,
            screenFrame: CGRect(x: 0, y: 0, width: screenRect.width, height: screenRect.height),
            onSave: { [weak self] frame in
                // Convert SwiftUI (Top-Left) to Cocoa (Bottom-Left)
                // cocoaY = screenHeight - (swiftUI_Y + height)
                let cocoaY = screenRect.height - (frame.origin.y + frame.height)
                let cocoaRect = CGRect(x: frame.origin.x, y: cocoaY, width: frame.width, height: frame.height)
                
                if let data = try? JSONEncoder().encode(cocoaRect) {
                    UserDefaults.standard.set(data, forKey: AppDefaults.Keys.popupFrameRect)
                }
                
                DispatchQueue.main.async {
                    self?.editorWindow?.close()
                    self?.editorWindow = nil
                }
            },
            onCancel: { [weak self] in
                DispatchQueue.main.async {
                    self?.editorWindow?.close()
                    self?.editorWindow = nil
                }
            }
        )
        
        let window = NSWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        editorWindow = window
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .serif))
            .foregroundColor(AppColors.text.opacity(0.8))
            .textCase(.uppercase)
            .kerning(0.5)
    }
}

struct APIKeyInput: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var isSecure: Bool = true  // Default to secure (密文)
    
    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 13, design: .serif))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(AppColors.primary.opacity(0.05))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.primary.opacity(0.1), lineWidth: 0.5))
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(AppColors.primary.opacity(0.05))
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.primary.opacity(0.1), lineWidth: 0.5))
            }
        }
    }
}

struct PromptsSection: View {
    @AppStorage(AppDefaults.Keys.presetModeEnabled) private var presetModeEnabled: Bool = AppDefaults.presetModeEnabled
    @AppStorage(AppDefaults.Keys.selectedPresetId) private var selectedPresetId: String = AppDefaults.selectedPresetId
    @State private var presets: [PromptPreset] = []
    @State private var editingPreset: PromptPreset?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Prompts".localized)
            
            // Preset Mode Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("启用预设模式".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.primary)
                    Text("关闭时为临时自定义模式；开启后选择预设".localized)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                Spacer()
                ElegantToggle(isOn: $presetModeEnabled)
            }
            
            Divider().opacity(0.3)
            
            // Preset Selection (Only visible when preset mode is enabled)
            if presetModeEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择预设".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.primary)
                    
                    // Default Translation Preset (Built-in)
                    PresetRadioRow(
                        id: AppDefaults.selectedPresetId,
                        name: "默认翻译".localized,
                        description: "Standard translation mode".localized,
                        isSelected: selectedPresetId == AppDefaults.selectedPresetId,
                        onSelect: { selectedPresetId = AppDefaults.selectedPresetId }
                    )
                    
                    Divider().opacity(0.3)
                    
                    // User Presets Header
                    HStack {
                        Text("自定义预设".localized)
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            editingPreset = PromptPreset(id: UUID(), name: "", inputPerception: "", outputInstruction: "")
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(5)
                                .background(Color.primary.opacity(0.05))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // User Presets List
                    if presets.isEmpty {
                        Text("暂无自定义预设".localized)
                            .font(.system(size: 12, design: .serif))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(presets) { preset in
                                PresetRadioRow(
                                    id: preset.id.uuidString,
                                    name: preset.name,
                                    description: "\(preset.inputPerception.prefix(30))...",
                                    isSelected: selectedPresetId == preset.id.uuidString,
                                    onSelect: { selectedPresetId = preset.id.uuidString },
                                    onEdit: {
                                        editingPreset = preset
                                    },
                                    onDelete: { deletePreset(preset) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadPresets() }
        .sheet(item: $editingPreset) { preset in
            let isNew = !presets.contains(where: { $0.id == preset.id })
            PresetEditor(preset: preset, isNew: isNew, onSave: { updated in
                if isNew {
                    addPreset(updated)
                } else {
                    updatePreset(updated)
                }
                editingPreset = nil
            }, onCancel: {
                editingPreset = nil
            })
        }
    }
    
    private func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: AppDefaults.Keys.savedPresets),
           let decoded = try? JSONDecoder().decode([PromptPreset].self, from: data) {
            presets = decoded
        }
    }
    
    private func addPreset(_ preset: PromptPreset) {
        presets.append(preset)
        persistPresets()
    }
    
    private func updatePreset(_ preset: PromptPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
            persistPresets()
        }
    }
    
    private func deletePreset(_ preset: PromptPreset) {
        presets.removeAll { $0.id == preset.id }
        // Reset to default translation if deleting currently selected preset
        if selectedPresetId == preset.id.uuidString {
            selectedPresetId = AppDefaults.selectedPresetId
        }
        persistPresets()
    }
    
    private func persistPresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: AppDefaults.Keys.savedPresets)
        }
    }
}

struct PresetRow: View {
    let preset: PromptPreset
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Radio Button
            Button(action: onSelect) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundColor(.primary)
                Text(preset.inputPerception.prefix(30) + "...")
                    .font(.system(size: 11, design: .serif))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .opacity(0.6)
        }
        .padding(10)
        .background(isActive ? Color.accentColor.opacity(0.05) : Color.primary.opacity(0.02))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

// Radio-style preset row for mode selection
struct PresetRadioRow: View {
    let id: String
    let name: String
    let description: String
    let isSelected: Bool
    let onSelect: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Swiss Indicator: A small, precise rectangle (Consistent with Sidebar)
            Rectangle()
                .fill(isSelected ? Color.primary : Color.clear)
                .frame(width: 2, height: 12)
                .opacity(isSelected ? 1 : 0)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .serif))
                    .foregroundColor(.primary)
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11, design: .serif))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Actions (only for user presets)
            if let onEdit = onEdit, let onDelete = onDelete {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .opacity(0.6)
            }
        }
        .padding(.vertical, 8) // Increased vertical padding for breathing room
        .padding(.horizontal, 4) // Minimal horizontal padding
        .contentShape(Rectangle()) // Make full row clickable
        .onTapGesture {
            onSelect()
        }
    }
}

struct PresetEditor: View {
    @State private var name: String = ""
    @State private var inputPerception: String = ""
    @State private var outputInstruction: String = ""
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, input, output
    }
    
    let preset: PromptPreset
    let isNew: Bool
    let onSave: (PromptPreset) -> Void
    let onCancel: () -> Void
    
    init(preset: PromptPreset, isNew: Bool, onSave: @escaping (PromptPreset) -> Void, onCancel: @escaping () -> Void) {
        self.preset = preset
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text(isNew ? "New Preset".localized : "Edit Preset".localized)
                .font(.system(size: 18, weight: .medium, design: .serif))
                .foregroundColor(.primary)
                .padding(.top, 8)
            
            VStack(spacing: 16) {
                StyledInputGroup(label: "Name".localized) {
                    TextField("e.g. Code Audit".localized, text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($focusedField, equals: .name)
                        .padding(10)
                }
                
                StyledInputGroup(label: "Input Perception".localized) {
                    ZStack(alignment: .topLeading) {
                        if inputPerception.isEmpty {
                            Text("How AI should understand the input...".localized)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.leading, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        
                        SmoothEditor(text: $inputPerception)
                            .frame(height: 80)
                    }
                    .padding(5)
                }
                
                StyledInputGroup(label: "Output Instruction".localized) {
                    ZStack(alignment: .topLeading) {
                        if outputInstruction.isEmpty {
                            Text("How AI should format the output...".localized)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary.opacity(0.5))
                                .padding(.leading, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        
                        SmoothEditor(text: $outputInstruction)
                            .frame(height: 120)
                    }
                    .padding(5)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                
                Button(action: {
                    let newPreset = PromptPreset(
                        id: preset.id,
                        name: name.isEmpty ? "Untitled" : name,
                        inputPerception: inputPerception,
                        outputInstruction: outputInstruction
                    )
                    onSave(newPreset)
                }) {
                    Text("Save".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(name.isEmpty ? Color.gray.opacity(0.3) : AppColors.primary)
                        )
                        .shadow(color: AppColors.primary.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 420)
        .background(ThemeBackground())
        .onAppear {
            name = preset.name
            inputPerception = preset.inputPerception
            outputInstruction = preset.outputInstruction
            if isNew {
                focusedField = .name
            }
        }
    }
}

struct StyledInputGroup<Content: View>: View {
    let label: String
    let content: Content
    
    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundColor(.secondary)
                .padding(.leading, 2)
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                
                content
            }
        }
    }
}

struct SmoothEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String?
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = YisiScrollView()
        scrollView.drawsBackground = false
        
        let textView = NSTextView()
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 5, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        
        textView.delegate = context.coordinator
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SmoothEditor
        
        init(_ parent: SmoothEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
    }
}

struct ShortcutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Shortcuts".localized)
            
            HStack {
                Text("Activate".localized)
                    .font(.system(size: 13, design: .serif))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                
                ShortcutRecorder()
            }
            
            HStack {
                Text("Screenshot".localized)
                    .font(.system(size: 13, design: .serif))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                
                ScreenshotShortcutRecorder()
            }
            
            Text("Press the key combination you want to use.".localized)
                .font(.system(size: 12, design: .serif))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.top, 4)
        }
    }
}

struct LearnedRulesSection: View {
    @State private var rules: [UserLearnedRule] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var editingRule: UserLearnedRule?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with + button
            HStack {
                SectionHeader(title: "Learned Rules".localized)
                
                Spacer()
                
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.primary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Add rule manually".localized)
            }
            
            Text("Translation rules learned from your corrections.".localized)
                .font(.system(size: 13, design: .serif))
                .foregroundColor(.secondary)
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding()
            } else if rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("No rules learned yet".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.secondary)
                    Text("Edit translations and click Improve to start learning.".localized)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rules) { rule in
                        RuleCard(
                            rule: rule,
                            onDelete: { deleteRule(rule) },
                            onEdit: { editingRule = rule }
                        )
                    }
                }
            }
        }
        .onAppear {
            loadRules()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LearnedRuleAdded"))) { _ in
            loadRules()
        }
        .sheet(isPresented: $showAddSheet) {
            AddRuleSheet(onSave: { reasoning, origin, ai, better in
                addManualRule(reasoning: reasoning, origin: origin, ai: ai, better: better)
            }, onCancel: {
                showAddSheet = false
            })
        }
        .sheet(item: $editingRule) { rule in
            EditRuleSheet(rule: rule, onSave: { updatedRule in
                updateRule(updatedRule)
                editingRule = nil
            }, onCancel: {
                editingRule = nil
            })
        }
    }
    
    private func loadRules() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedRules = LearningManager.shared.getAllRules()
            DispatchQueue.main.async {
                rules = loadedRules
                isLoading = false
            }
        }
    }
    
    private func deleteRule(_ rule: UserLearnedRule) {
        do {
            try LearningManager.shared.deleteRule(id: rule.id)
            print("DEBUG: Successfully deleted rule: \(rule.id)")
            loadRules()
        } catch {
            print("ERROR: Failed to delete rule: \(error)")
        }
    }
    
    private func updateRule(_ rule: UserLearnedRule) {
        do {
            try LearningManager.shared.updateRule(rule)
            print("DEBUG: Successfully updated rule: \(rule.id)")
            loadRules()
        } catch {
            print("ERROR: Failed to update rule: \(error)")
        }
    }
    
    private func addManualRule(reasoning: String, origin: String, ai: String, better: String) {
        do {
            try LearningManager.shared.addManualRule(
                reasoning: reasoning,
                originalText: origin,
                aiTranslation: ai,
                userCorrection: better
            )
            showAddSheet = false
            loadRules()
        } catch {
            print("ERROR: Failed to add manual rule: \(error)")
        }
    }
}


// MARK: - Edit Rule Sheet

struct EditRuleSheet: View {
    let rule: UserLearnedRule
    let onSave: (UserLearnedRule) -> Void
    let onCancel: () -> Void
    
    @State private var editedReasoning: String
    @State private var editedCorrection: String
    
    init(rule: UserLearnedRule, onSave: @escaping (UserLearnedRule) -> Void, onCancel: @escaping () -> Void) {
        self.rule = rule
        self.onSave = onSave
        self.onCancel = onCancel
        _editedReasoning = State(initialValue: rule.reasoning)
        _editedCorrection = State(initialValue: rule.userCorrection)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Edit Rule".localized)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundColor(.primary)
                .padding(.top, 24)
                .padding(.bottom, 20)
            
            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Rule Content
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rule".localized)
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $editedReasoning)
                            .font(.system(size: 13, design: .serif))
                            .frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Evidence Section
                    VStack(spacing: 12) {
                        // Origin (Read Only)
                        ReadOnlyField(label: "Origin", text: rule.originalText)
                        
                        // AI (Read Only)
                        ReadOnlyField(label: "AI", text: rule.aiTranslation)
                        
                        // Better (Editable)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Better".localized)
                                .font(.system(size: 11, weight: .medium, design: .serif))
                                .foregroundColor(AppColors.primary.opacity(0.8))
                            
                            TextField("Your correction...", text: $editedCorrection)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium, design: .serif))
                                .padding(10)
                                .background(Color.primary.opacity(0.03))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(AppColors.primary.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            
            Spacer(minLength: 16)
            
            // Footer Actions
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                
                Button(action: {
                    let updated = UserLearnedRule(
                        id: rule.id,
                        originalText: rule.originalText,
                        aiTranslation: rule.aiTranslation,
                        userCorrection: editedCorrection.trimmingCharacters(in: .whitespaces),
                        reasoning: editedReasoning.trimmingCharacters(in: .whitespaces),
                        rulePattern: rule.rulePattern,
                        category: rule.category,
                        createdAt: rule.createdAt,
                        usageCount: rule.usageCount
                    )
                    onSave(updated)
                }) {
                    Text("Save".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppColors.primary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(editedReasoning.isEmpty || editedCorrection.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(24)
        }
        .frame(width: 400, height: 500) // Fixed size, larger comfortable window
        .background(ThemeBackground())
    }
}

struct ReadOnlyField: View {
    let label: String
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.localized)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(text.isEmpty ? "-" : text)
                .font(.system(size: 13, design: .serif))
                .foregroundColor(.secondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(6)
        }
    }
}

// MARK: - Add Rule Sheet (Refactored)

struct AddRuleSheet: View {
    let onSave: (String, String, String, String) -> Void
    let onCancel: () -> Void
    
    @State private var ruleContent: String = ""
    @State private var attachExample: Bool = false
    @State private var origin: String = ""
    @State private var aiTranslation: String = ""
    @State private var betterTranslation: String = ""
    
    private var canSave: Bool {
        let ruleValid = !ruleContent.trimmingCharacters(in: .whitespaces).isEmpty
        if attachExample {
            return ruleValid &&
                !origin.trimmingCharacters(in: .whitespaces).isEmpty &&
                !aiTranslation.trimmingCharacters(in: .whitespaces).isEmpty &&
                !betterTranslation.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return ruleValid
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Add Rule".localized)
                .font(.system(size: 16, weight: .medium, design: .serif))
                .foregroundColor(.primary)
                .padding(.top, 24)
                .padding(.bottom, 20)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Rule Content (Required)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rule Content".localized)
                            .font(.system(size: 12, weight: .medium, design: .serif))
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $ruleContent)
                            .font(.system(size: 13, design: .serif))
                            .frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Attach Example Toggle
                    HStack {
                        Text("Attach Example".localized)
                            .font(.system(size: 13, design: .serif))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        ElegantToggle(isOn: $attachExample)
                    }
                    
                    // Example Fields (Conditional)
                    if attachExample {
                        VStack(spacing: 12) {
                            AddRuleField(label: "Origin".localized, text: $origin, placeholder: "Original text...")
                            AddRuleField(label: "AI".localized, text: $aiTranslation, placeholder: "AI translation...")
                            AddRuleField(label: "Better".localized, text: $betterTranslation, placeholder: "Your correction...", highlight: true)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 24)
            }
            
            Spacer(minLength: 16)
            
            // Actions
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                
                Button(action: {
                    onSave(
                        ruleContent.trimmingCharacters(in: .whitespaces),
                        attachExample ? origin.trimmingCharacters(in: .whitespaces) : "",
                        attachExample ? aiTranslation.trimmingCharacters(in: .whitespaces) : "",
                        attachExample ? betterTranslation.trimmingCharacters(in: .whitespaces) : ""
                    )
                }) {
                    Text("Save".localized)
                        .font(.system(size: 13, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(canSave ? AppColors.primary : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(24)
        }
        .frame(width: 400, height: 500) // Fixed size to prevent window resize glitches
        .background(ThemeBackground())
    }
}

struct AddRuleField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var highlight: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundColor(highlight ? AppColors.primary.opacity(0.8) : .secondary.opacity(0.6))
                .frame(width: 40, alignment: .leading)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .serif))
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(4)
        }
    }
}


struct RuleCard: View {
    let rule: UserLearnedRule
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Rule Text (Brief)
            Text(rule.reasoning)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Actions
            HStack(spacing: 8) {
                // Edit Trigger (Visual only, whole card is clickable)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.3))
                
                // Delete Button (Separate action)
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.3))
                        .padding(4)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}

// Helper view for consistent field rows (kept for compatibility)
struct RuleFieldRow: View {
    let label: String
    let value: String
    var labelColor: Color = .secondary.opacity(0.6)
    var valueColor: Color = .secondary.opacity(0.8)
    var isEditable: Bool = false
    var isBold: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .foregroundColor(labelColor)
                .frame(width: 40, alignment: .leading)
            
            Text(value)
                .font(.system(size: 12, weight: isBold ? .medium : .regular, design: .serif))
                .foregroundColor(valueColor)
                .lineLimit(2)
        }
    }
}



extension RuleCategory {
    var displayName: String {
        switch self {
        case .attributeToVerb: return "Attribute→Verb"
        case .metaphor: return "Metaphor"
        case .terminology: return "Terminology"
        case .style: return "Style"
        case .other: return "Other"
        }
    }
}

struct CustomDropdown: View {
    @Binding var selection: String
    let options: [String]
    var displayNames: [String]? = nil
    
    @State private var isExpanded = false
    
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    selection = option
                }) {
                    Text(displayName(for: option))
                }
            }
        } label: {
            HStack {
                Text(displayName(for: selection))
                    .font(.system(size: 13, design: .serif))
                    .foregroundColor(.primary)
                Spacer()
                // Removed redundant chevron
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(width: 160)
            .background(AppColors.primary.opacity(0.05))
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.primary.opacity(0.1), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
    
    private func displayName(for option: String) -> String {
        if let displayNames = displayNames, let index = options.firstIndex(of: option) {
            return displayNames[index]
        }
        return option
    }
}

struct ElegantToggle: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) var currentColorScheme
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.toggle()
            }
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? AppColors.primary : (currentColorScheme == ColorScheme.dark ? Color.white.opacity(0.25) : AppColors.primary.opacity(0.15)))
                    .frame(width: 32, height: 18)
                
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .padding(2)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ShortcutRecorder: View {
    @State private var isRecording = false
    @State private var currentShortcut: String = ""
    @State private var monitor: Any?
    @State private var showHint = false

    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            HStack {
                if isRecording {
                    Text(showHint ? "Requires Cmd/Ctrl/Opt".localized : "Press keys...".localized)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(showHint ? .orange : .accentColor)
                    Spacer()
                    Image(systemName: "record.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse)
                } else {
                    Text(currentShortcut.isEmpty ? "Record Shortcut".localized : currentShortcut)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.primary)
                    Spacer()
                    if !currentShortcut.isEmpty {
                        Button(action: {
                            resetShortcut()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(width: 160)
            .background(isRecording ? AppColors.primary.opacity(0.1) : AppColors.primary.opacity(0.05))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isRecording ? AppColors.primary.opacity(0.3) : AppColors.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            updateDisplay()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        // Add a local monitor to capture keys
        // We use .keyDown to capture the combination
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil // Consume the event
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    
    private func resetShortcut() {
        GlobalShortcutManager.shared.updateShortcut(keyCode: 16, modifiers: [.command, .control])
        updateDisplay()
    }
    
    private func updateDisplay() {
        let keyCode = UserDefaults.standard.integer(forKey: AppDefaults.Keys.globalShortcutKey)
        let modifiers = UserDefaults.standard.integer(forKey: AppDefaults.Keys.globalShortcutModifiers)
        
        if keyCode != 0 {
            currentShortcut = shortcutString(keyCode: UInt16(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
        } else {
            currentShortcut = "⌘⌃Y" // Default
        }
    }
    
    private func handleKeyDown(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // Ignore standalone modifier presses
        if event.type == .flagsChanged {
            return
        }

        // Escape to cancel
        if keyCode == 53 {
            stopRecording()
            return
        }

        let hasPrimaryModifier = flags.contains(.command)
            || flags.contains(.control)
            || flags.contains(.option)
        guard hasPrimaryModifier else {
            showHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showHint = false }
            return
        }

        // Save shortcut
        GlobalShortcutManager.shared.updateShortcut(keyCode: keyCode, modifiers: flags)
        updateDisplay()
        stopRecording()
    }
    
    private func shortcutString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var string = ""
        if modifiers.contains(.command) { string += "⌘" }
        if modifiers.contains(.control) { string += "⌃" }
        if modifiers.contains(.option) { string += "⌥" }
        if modifiers.contains(.shift) { string += "⇧" }
        
        // Simple key mapping
        switch keyCode {
        case 0: string += "A"
        case 1: string += "S"
        case 2: string += "D"
        case 3: string += "F"
        case 4: string += "H"
        case 5: string += "G"
        case 6: string += "Z"
        case 7: string += "X"
        case 8: string += "C"
        case 9: string += "V"
        case 11: string += "B"
        case 12: string += "Q"
        case 13: string += "W"
        case 14: string += "E"
        case 15: string += "R"
        case 16: string += "Y"
        case 17: string += "T"
        case 18: string += "1"
        case 19: string += "2"
        case 20: string += "3"
        case 21: string += "4"
        case 22: string += "6"
        case 23: string += "5"
        case 24: string += "="
        case 25: string += "9"
        case 26: string += "7"
        case 27: string += "-"
        case 28: string += "8"
        case 29: string += "0"
        case 30: string += "]"
        case 31: string += "O"
        case 32: string += "U"
        case 33: string += "["
        case 34: string += "I"
        case 35: string += "P"
        case 37: string += "L"
        case 38: string += "J"
        case 39: string += "'"
        case 40: string += "K"
        case 41: string += ";"
        case 42: string += "\\"
        case 43: string += ","
        case 44: string += "/"
        case 45: string += "N"
        case 46: string += "M"
        case 47: string += "."
        case 50: string += "`"
        default: string += "?"
        }
        
        return string
    }
}
