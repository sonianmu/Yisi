import Cocoa
import SwiftUI

struct TranslationView: View {
    @State var originalText: String
    var errorMessage: String?
    @State private var translatedText: String = ""
    @State private var isTranslating: Bool = false
    @State private var sourceLanguage: Language
    @State private var targetLanguage: Language
    @FocusState private var isInputFocused: Bool
    @AppStorage(AppDefaults.Keys.closeMode) private var closeMode: String = AppDefaults.closeMode
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var isImproving: Bool = false
    @State private var originalAiTranslation: String = ""
    @State private var savedOriginalText: String = ""
    @AppStorage(AppDefaults.Keys.enableImproveFeature) private var enableImproveFeature: Bool = AppDefaults.enableImproveFeature
    @AppStorage(AppDefaults.Keys.translationEngine) private var translationEngine: String = AppDefaults.translationEngine
    @State private var showAnalysisResult: Bool = false
    @State private var analysisReasoning: String = ""
    @State private var showImproveSuccess: Bool = false
    @State private var showLanguagePackPrompt: Bool = false
    @State private var missingPackSource: String = ""
    @State private var missingPackTarget: String = ""
    
    @AppStorage("enable_custom_mode_popup") private var enableCustomModePopup: Bool = false
    @AppStorage(AppDefaults.Keys.presetModeEnabled) private var presetModeEnabled: Bool = AppDefaults.presetModeEnabled
    @AppStorage(AppDefaults.Keys.selectedPresetId) private var selectedPresetId: String = AppDefaults.selectedPresetId
    @AppStorage(AppDefaults.Keys.externalTranslator) private var externalTranslatorID: String = ""
    @ObservedObject private var modules = ModuleStore.shared
    /// A preset chosen by its own shortcut; overrides the mode chosen in Settings for this popup.
    private let shortcutMode: Mode?
    /// The running request. Replaced by the next one and cancelled when the popup closes.
    @State private var work: Task<Void, Never>?
    /// True while a module streams text into the output.
    @State private var isStreaming: Bool = false
    @State private var customInputPerception: String = ""
    @State private var customOutputInstruction: String = ""
    @State private var inputPerceptionHeight: CGFloat = 24
    @State private var outputInstructionHeight: CGFloat = 24
    
    // 图片上下文（截图功能）
    @State private var imageContext: NSImage?
    /// 是否为图片模式（一旦进入图片模式，即使删除图片也保持）
    @State private var isImageMode: Bool = false
    
    /// What this popup does with its input.
    enum Mode: Equatable {
        case translation
        case custom
        /// A hand-written “这是…，请…” preset.
        case preset(PromptPreset)
        /// A preset module built by the user's agent.
        case module(Module)

        var module: Module? {
            if case .module(let module) = self { return module }
            return nil
        }

        /// The built-in pipeline's prompt for this mode; modules bring their own.
        var promptMode: PromptMode {
            switch self {
            case .custom: return .temporaryCustom
            case .preset(let preset): return .userPreset(preset)
            case .translation, .module: return .defaultTranslation
            }
        }
    }

    var mode: Mode {
        if let shortcutMode { return shortcutMode }
        if translationEngine == "external" { return .translation }
        if !presetModeEnabled { return .custom }
        if let id = Module.id(fromSelection: selectedPresetId) {
            if let module = modules.module(id), module.role == .preset { return .module(module) }
        } else if let preset = PromptPreset.saved().first(where: { $0.id.uuidString == selectedPresetId }) {
            return .preset(preset)
        }
        return .translation
    }

    var outputPlaceholder: String {
        if translationEngine != "ai" && mode == .translation {
            return "Translation result will appear here...".localized
        }
        switch mode {
        case .translation: return "翻译结果将显示在这里...".localized
        case .custom: return "处理结果将显示在这里...".localized
        case .preset, .module: return "输出结果将显示在这里...".localized
        }
    }

    init(originalText: String, errorMessage: String? = nil, imageContext: NSImage? = nil, startInImageMode: Bool = false,
         mode: Mode? = nil) {
        self.originalText = originalText
        self.errorMessage = errorMessage
        self.shortcutMode = mode
        _imageContext = State(initialValue: imageContext)
        _isImageMode = State(initialValue: imageContext != nil || startInImageMode)
        
        let defaultSource = UserDefaults.standard.string(forKey: AppDefaults.Keys.defaultSourceLanguage) ?? Language.auto.rawValue
        let defaultTarget = UserDefaults.standard.string(forKey: AppDefaults.Keys.defaultTargetLanguage) ?? Language.simplifiedChinese.rawValue
        
        _sourceLanguage = State(initialValue: Language(rawValue: defaultSource) ?? .auto)
        _targetLanguage = State(initialValue: Language(rawValue: defaultTarget) ?? .simplifiedChinese)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // System Translation Host (invisible, enables translation task)
            if #available(macOS 15.0, *) {
                SystemTranslationHost()
            }
            
            // Custom Mode Input Fields (Only visible in Temporary Custom Mode)
            if mode == .custom {
                VStack(alignment: .leading, spacing: 16) {
                    // Narrative Input Structure
                    HStack(alignment: .top, spacing: 6) {
                        Text("I perceive this as".localized)
                            .font(.system(size: 16, weight: .light, design: .serif))
                            .foregroundColor(.secondary)
                            // .padding(.top, 2) Removed for alignment with zero-inset editor
                        
                        NarrativeTextField(
                            text: $customInputPerception,
                            height: $inputPerceptionHeight,
                            placeholder: "Ancient Poetry".localized
                        )
                        .frame(minWidth: 120)
                        
                        Text(",")
                            .font(.system(size: 16, weight: .light, design: .serif))
                            .foregroundColor(.secondary)
                            // .padding(.top, 2)
                    }
                    
                    HStack(alignment: .top, spacing: 6) {
                        Text("please".localized)
                            .font(.system(size: 16, weight: .light, design: .serif))
                            .foregroundColor(.secondary)
                            // .padding(.top, 2)
                        
                        NarrativeTextField(
                            text: $customOutputInstruction,
                            height: $outputInstructionHeight,
                            placeholder: "translate to modern English".localized
                        )
                        .frame(minWidth: 180)
                        
                        Text(".")
                            .font(.system(size: 16, weight: .light, design: .serif))
                            .foregroundColor(.secondary)
                            // .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .padding(.trailing, closeMode == "xButton" ? 40 : 0) // Reserve space for gravity orb
                .background(Color.primary.opacity(0.01)) // Almost invisible background
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: inputPerceptionHeight)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: outputInstructionHeight)

                Divider().opacity(0.3)
            }

            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(errorMessage).font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                    Spacer()
                    Button("Open Settings".localized) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }.buttonStyle(.borderedProminent).controlSize(.small)
                }.padding().background(Color.orange.opacity(0.1))
            }
            

            
            // Analysis Result Banner - REMOVED
            
            // Language Selectors - Top Position (Only in Default Translation Mode)
            if mode == .translation {
                HStack {
                    HStack(spacing: 8) {
                        LanguageSelector(selection: $sourceLanguage, languages: Language.sourceLanguages)
                        
                        Button(action: swapLanguages) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Swap languages".localized)
                        
                        LanguageSelector(selection: $targetLanguage, languages: Language.targetLanguages)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.02))
                .transition(.opacity)

                Divider().opacity(0.3)
            }
            
            // Main Content Area - Layout depends on mode
            if isImageMode {
                // 图片模式：上下布局（图片/上传区 + 输出）
                VStack(spacing: 0) {
                    // 图片预览区 或 上传占位符
                    if let image = imageContext {
                        // 有图片：显示预览
                        HStack(spacing: 12) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 120)
                                .cornerRadius(8)
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Screenshot".localized)
                                    .font(.system(size: 12, weight: .medium, design: .serif))
                                    .foregroundColor(.secondary)
                                
                                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    imageContext = nil
                                    translatedText = ""
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(Color.primary.opacity(0.02))
                    } else {
                        // 无图片：显示优雅的上传占位符
                        Button(action: selectImageFromFile) {
                            VStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.primary.opacity(0.08))
                                        .frame(width: 56, height: 56)
                                    
                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .light))
                                        .foregroundColor(AppColors.primary.opacity(0.6))
                                }
                                
                                Text("Click to upload image".localized)
                                    .font(.system(size: 13, weight: .medium, design: .serif))
                                    .foregroundColor(.secondary)
                                
                                Text("or drag & drop".localized)
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .background(Color.primary.opacity(0.02))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                            handleImageDrop(providers: providers)
                        }
                    }
                    
                    Divider().opacity(0.3)
                    
                    // 输出区
                    ZStack(alignment: .topLeading) {
                        MacEditorView(text: .constant(translatedText))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(isTranslating ? 0 : 1)
                            .overlay(alignment: .topLeading) {
                                Group {
                                    if isTranslating {
                                        HarmonicFlowView(text: "Recognizing image...".localized)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 20)
                                    } else if translatedText.isEmpty {
                                        Text(translationEngine != "ai" ? "Translation result will appear here...".localized : "AI recognition result will appear here...".localized)
                                            .font(.system(size: 16, weight: .light, design: .serif))
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 20)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .clipped()
                            }
                    }
                    .background(Color.clear)
                }
            } else {
                // 文本模式：左右布局（输入 + 输出）
                HStack(spacing: 0) {
                    CustomTextEditor(text: $originalText, placeholder: "Type or paste text..".localized)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(width: 1)
                    
                    // Output area - Always editable
                    ZStack(alignment: .topLeading) {
                        MacEditorView(text: $translatedText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(isTranslating ? 0 : 1)
                            .overlay(alignment: .topLeading) {
                                Group {
                                    if isTranslating {
                                        HarmonicFlowView(text: originalText)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 20)
                                    } else if translatedText.isEmpty {
                                        Text(outputPlaceholder)
                                            .font(.system(size: 16, weight: .light, design: .serif))
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 20)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .clipped()
                            }
                    }
                    .background(Color.clear)
                }
            }
            
            if showLanguagePackPrompt {
                Divider().opacity(0.3)
                
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.primary)
                    
                    Text("Language pack required for offline translation.".localized)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    Spacer()
                    
                    if #available(macOS 15.0, *) {
                        Button(action: {
                            SystemTranslationManager.shared.requestDownload(
                                source: missingPackSource,
                                target: missingPackTarget
                            )
                        }) {
                            Text("Download".localized)
                                .font(.system(size: 11, weight: .medium, design: .serif))
                                .foregroundColor(AppColors.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppColors.primary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(AppColors.primary.opacity(0.04))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Bottom Bar
            HStack {
                
                Spacer()
                
                // Right Side: Actions
                HStack(spacing: 12) {
                    // Smart Improvement Button (Text Mode Only, AI Engine Only, Feature Enabled)
                    if !isImageMode && translationEngine == "ai" && enableImproveFeature && mode.module == nil {
                        SmartImprovementButton(
                            hasChanges: !translatedText.isEmpty && !originalAiTranslation.isEmpty && translatedText != originalAiTranslation,
                            isLoading: isImproving,
                            showSuccess: showImproveSuccess,
                            action: { start { await improveWithAI() } }
                        )
                    }
                    
                    // Yisi Button (The Living Verb)
                    YisiButton(isLoading: isTranslating || isStreaming || isImproving) {
                        if isImageMode && imageContext != nil {
                            start { await performImageRecognition() }
                        } else {
                            start { await performTranslation() }
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }.padding(.horizontal, 20).padding(.vertical, 16).background(Color.primary.opacity(0.03))
        }.background(ThemeBackground())
        // 3. The content fills the window, titlebar included, so its corners are the window's.
        .clipShape(WindowCorner.window)
        .overlay(WindowCorner.window.stroke(Color.primary.opacity(0.1), lineWidth: 1))
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            if closeMode == "xButton" {
                CloseButton {
                    WindowManager.shared.close()
                }
                .padding(8) // Move closer to the edge (was 12)
                .offset(x: 4, y: -4) // Push slightly out
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background(WindowAccessor(window: $window))
        .onExitCommand {
            if closeMode == "escKey" {
                WindowManager.shared.close()
            }
        }.onAppear {
            // Run straight away unless the user still has to write the "这是…，请…" instruction.
            guard mode != .custom else { return }
            if isImageMode && imageContext != nil {
                start { await performImageRecognition() }
            } else if !originalText.isEmpty {
                start { await performTranslation() }
            }
        }
        .onDisappear { work?.cancel() }
        .onChange(of: inputPerceptionHeight) { _, newValue in
            adjustWindowHeight(delta: newValue - 24) // 24 is base height
        }
        .onChange(of: outputInstructionHeight) { _, newValue in
            adjustWindowHeight(delta: newValue - 24)
        }
    }
    
    @State private var window: NSWindow?
    @State private var lastInputHeight: CGFloat = 24
    @State private var lastOutputHeight: CGFloat = 24
    
    private func adjustWindowHeight(delta: CGFloat) {
        guard let window = window else { return }
        
        // Calculate total delta based on both fields
        // We need to track the previous height to know the incremental change
        // But here we are getting the absolute height from the binding
        
        // Calculate the difference in total height to resize window
        
        // We also need to know the current window height to apply the difference?
        // No, we should probably just resize the window based on the content change.
        // But SwiftUI updates happen frequently.
        
        // Let's rely on the fact that we want the window to grow by the *change* in height.
        // We need to store the previous total height.
        
        let currentTotal = inputPerceptionHeight + outputInstructionHeight
        let previousTotal = lastInputHeight + lastOutputHeight
        let diff = currentTotal - previousTotal
        
        if diff != 0 {
            var frame = window.frame
            frame.size.height += diff
            frame.origin.y -= diff // Grow upwards (Cocoa coords) or downwards?
            // Cocoa origin is bottom-left.
            // To grow downwards (keeping top fixed), we need to decrease origin.y by the growth amount.
            // To grow upwards (keeping bottom fixed), we just increase height.
            // Usually we want to grow downwards for a dropdown/input at top.
            
            window.setFrame(frame, display: true, animate: true)
            
            lastInputHeight = inputPerceptionHeight
            lastOutputHeight = outputInstructionHeight
        }
    }
    
    // MARK: - Image Upload Helpers
    
    /// 从文件选择器选择图片
    private func selectImageFromFile() {
        // 临时禁用关闭检测，避免打开文件选择器时窗口关闭
        WindowManager.shared.suspendCloseDetection()
        
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .heic, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an image to recognize".localized
        panel.prompt = "Select".localized
        
        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                withAnimation(.easeOut(duration: 0.2)) {
                    imageContext = image
                    translatedText = ""
                }
                // Auto-process image (like text mode)
                // Only in non-custom mode where user doesn't need to specify instructions first
                if mode != .custom {
                    start { await performImageRecognition() }
                }
            }
        }
        
        // 恢复关闭检测
        WindowManager.shared.resumeCloseDetection()
    }
    
    /// 处理拖放图片
    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        // 尝试加载图片
        if provider.canLoadObject(ofClass: NSImage.self) {
            provider.loadObject(ofClass: NSImage.self) { image, error in
                if let image = image as? NSImage {
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.imageContext = image
                            self.translatedText = ""
                        }
                        // Auto-process image after drop (like text mode)
                        if self.mode != .custom {
                            self.start { await self.performImageRecognition() }
                        }
                    }
                }
            }
            return true
        }
        
        // 尝试加载文件 URL
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   let image = NSImage(contentsOf: url) {
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.imageContext = image
                            self.translatedText = ""
                        }
                        // Auto-process image after drop (like text mode)
                        if self.mode != .custom {
                            self.start { await self.performImageRecognition() }
                        }
                    }
                }
            }
            return true
        }
        
        return false
    }
    
    /// Starts a request, replacing any that is still running.
    private func start(_ operation: @escaping @MainActor () async -> Void) {
        work?.cancel()
        work = Task { @MainActor in await operation() }
    }

    /// The translator module selected under Translation → Other Sources.
    private var translatorModule: Module? {
        modules.modules(for: .translator).first { $0.id == externalTranslatorID }
    }

    private func performTranslation() async {
        guard !originalText.isEmpty else { return }
        switch mode {
        case .module(let module):
            await run(module, text: originalText, image: nil)
            return
        case .translation where translationEngine == "external":
            await runTranslator(text: originalText, image: nil)
            return
        default:
            break
        }
        isTranslating = true
        do {
            let promptMode = mode.promptMode
            if translationEngine == "system" && promptMode == .defaultTranslation {
                translatedText = try await performSystemTranslation()
            } else {
                translatedText = try await AIService.shared.processText(
                    originalText,
                    mode: promptMode,
                    sourceLanguage: sourceLanguage.rawValue,
                    targetLanguage: targetLanguage.rawValue,
                    userPerception: promptMode == .temporaryCustom ? customInputPerception : nil,
                    userInstruction: promptMode == .temporaryCustom ? customOutputInstruction : nil
                )
            }
            try Task.checkCancellation()
            originalAiTranslation = translatedText
            savedOriginalText = originalText
            withAnimation { showLanguagePackPrompt = false }
        } catch {
            show(error)
        }
        isTranslating = false
    }

    /// Streams a module's answer into the output. Text appears as soon as the first chunk arrives.
    private func run(_ module: Module, text: String, image: NSImage?, recordHistory: Bool = true) async {
        isTranslating = true
        isStreaming = false
        translatedText = ""
        defer { isTranslating = false; isStreaming = false }
        do {
            let request = ModuleRequest(text: text, image: image.flatMap(AIService.shared.imageToData),
                                        source: sourceLanguage.code, target: targetLanguage.code)
            var output = ""
            for try await chunk in try modules.run(module, request) {
                output += chunk
                if !isStreaming, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isStreaming = true
                    isTranslating = false
                }
                if isStreaming { translatedText = output }
            }
            let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw ModuleError.emptyResult }
            translatedText = result
            if recordHistory {
                HistoryManager.shared.addHistory(sourceText: text, targetText: result, sourceLanguage: sourceLanguage.rawValue,
                                                 targetLanguage: targetLanguage.rawValue, module: module, image: image)
            }
        } catch is CancellationError {
        } catch {
            translatedText = "\(module.name) · \(error.localizedDescription)"
        }
    }

    private func runTranslator(text: String, image: NSImage?) async {
        guard let module = translatorModule else {
            translatedText = "Choose a translation source in Settings → Translation → Other Sources.".localized
            return
        }
        await run(module, text: text, image: image, recordHistory: false)
    }

    private func show(_ error: Error) {
        if error is CancellationError { return }
        if let error = error as? SystemTranslationError, case .languagePackNotInstalled(let src, let tgt) = error {
            missingPackSource = src
            missingPackTarget = tgt
            withAnimation(.easeOut(duration: 0.2)) { showLanguagePackPrompt = true }
            translatedText = ""
            return
        }
        translatedText = "Error: \(error.localizedDescription)"
    }
    
    /// System Translation using macOS native Translation API
    private func performSystemTranslation() async throws -> String {
        try await SystemTranslation.translate(
            originalText,
            to: targetLanguage.code,
            from: sourceLanguage == .auto ? nil : sourceLanguage.code
        )
    }

    /// 图片识别 - 使用 PromptCoordinator 构建指令
    private func performImageRecognition() async {
        guard let image = imageContext else { return }
        switch mode {
        case .module(let module):
            await run(module, text: "", image: image)
            return
        case .translation where translationEngine == "external":
            await runTranslator(text: "", image: image)
            return
        default:
            break
        }
        isTranslating = true
        do {
            let promptMode = mode.promptMode
            if translationEngine == "system" && promptMode == .defaultTranslation {
                // Local OCR, then the system translation model.
                let extractedText = try await LocalVisionService.shared.recognizeText(from: image)
                translatedText = try await SystemTranslation.translate(
                    extractedText,
                    to: targetLanguage.code,
                    from: sourceLanguage == .auto ? nil : sourceLanguage.code
                )
            } else {
                let imageStrategy = UserDefaults.standard.string(forKey: AppDefaults.Keys.imageProcessingStrategy) ?? "ai_vision"

                if imageStrategy == "local_ocr" {
                    let extractedText = try await LocalVisionService.shared.recognizeText(from: image)

                    let wrappedText = """
                    [The user sent an image for the task above, \
                    but you are running in a text-only container and cannot view it directly. \
                    The system has extracted all text from the image via OCR as shown below. \
                    Please fulfill the user's task based solely on this text. \
                    If the task requires visual judgments (layout, color, etc.) that cannot be \
                    determined from text alone, state this clearly in your response.]

                    \(extractedText)
                    """

                    translatedText = try await AIService.shared.processText(
                        wrappedText,
                        mode: promptMode,
                        sourceLanguage: sourceLanguage.rawValue,
                        targetLanguage: targetLanguage.rawValue,
                        userPerception: promptMode == .temporaryCustom ? customInputPerception : nil,
                        userInstruction: promptMode == .temporaryCustom ? customOutputInstruction : nil
                    )
                } else {
                    translatedText = try await AIService.shared.processImage(
                        image, mode: promptMode, sourceLanguage: sourceLanguage.rawValue,
                        targetLanguage: targetLanguage.rawValue,
                        userPerception: promptMode == .temporaryCustom ? customInputPerception : nil,
                        userInstruction: promptMode == .temporaryCustom ? customOutputInstruction : nil)
                }
            }
            try Task.checkCancellation()
            originalAiTranslation = translatedText
            savedOriginalText = originalText
            withAnimation { showLanguagePackPrompt = false }
        } catch {
            show(error)
        }
        isTranslating = false
    }
    
    
    private func improveWithAI() async {
        print("DEBUG: improveWithAI called")
        guard !savedOriginalText.isEmpty && !originalAiTranslation.isEmpty && !translatedText.isEmpty else {
            print("DEBUG: Missing data for improve: original=\(savedOriginalText.isEmpty), ai=\(originalAiTranslation.isEmpty), translated=\(translatedText.isEmpty)")
            return
        }
        
        // Ensure user actually made changes
        guard translatedText != originalAiTranslation else {
            print("DEBUG: No changes detected, skipping improve")
            return
        }
        
        isImproving = true
        print("DEBUG: Starting analysis...")
        do {
            let rule = try await LearningManager.shared.analyzeCorrection(
                originalText: savedOriginalText,
                aiTranslation: originalAiTranslation,
                userCorrection: translatedText
            )
            print("DEBUG: Analysis complete. Rule received: \(rule.id)")
            
            // Successfully saved rule, update UI
            await MainActor.run {
                print("DEBUG: Updating UI on MainActor")
                
                // Update baseline to current text (prevents button re-activation)
                originalAiTranslation = translatedText
                
                // Show success indicator
                showImproveSuccess = true
                
                // Post notification to refresh Settings
                NotificationCenter.default.post(name: NSNotification.Name("LearnedRuleAdded"), object: nil)
                
                // Auto-hide after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showImproveSuccess = false
                    }
                }
            }
        } catch {
            // Show error in console
            print("Failed to improve: \(error.localizedDescription)")
            if let data = (error as NSError).userInfo["data"] as? Data,
               let jsonString = String(data: data, encoding: .utf8) {
                print("Raw response: \(jsonString)")
            }
        }
        isImproving = false
    }

    
    private func swapLanguages() {
        if sourceLanguage == .auto {
            sourceLanguage = targetLanguage
            targetLanguage = .english
        } else {
            let temp = sourceLanguage
            // Ensure the target language is valid for source (always true as source is superset)
            // Ensure the source language is valid for target (Auto is not valid target)
            if temp == .auto {
                 // Should be covered by first if, but for safety
                 sourceLanguage = targetLanguage
                 targetLanguage = .english
            } else {
                // Check if the current source is a valid target (it should be unless it's auto)
                if Language.targetLanguages.contains(temp) {
                     sourceLanguage = targetLanguage
                     targetLanguage = temp
                } else {
                    // Fallback if something weird happens
                    sourceLanguage = targetLanguage
                    targetLanguage = .english
                }
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct CustomTextEditor: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            MacEditorView(text: $text)
                .focused($isFocused)
            
            // Hide placeholder if text is not empty OR if the field is focused (to prevent overlap with input method candidates)
            if text.isEmpty && !isFocused {
                Text(placeholder)
                    .font(.system(size: 16, weight: .light, design: .serif))
                    .foregroundColor(AppColors.text.opacity(0.4))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }.background(Color.clear)
        .onTapGesture {
            isFocused = true
        }
    }
}



struct MacEditorView: NSViewRepresentable {
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = YisiScrollView()
        scrollView.verticalScroller?.controlSize = .mini

        let textView = NSTextView()
        textView.autoresizingMask = [.width, .height]
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = AppFont.shared.font
        textView.textColor = NSColor(AppColors.text)
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // 15 + the 5 pt line fragment padding puts text 20 pt in, on the popup's gutter.
        textView.textContainerInset = NSSize(width: 15, height: 20)
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
        Coordinator(text: $text)
    }
    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        
        init(text: Binding<String>) {
            _text = text
        }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

struct OutputTextView: NSViewRepresentable {
    let text: String
    let isEmpty: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = YisiScrollView()
        scrollView.verticalScroller?.controlSize = .mini

        let textView = NSTextView()
        textView.autoresizingMask = [.width, .height]
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true

        textView.font = AppFont.shared.font

        textView.textColor = NSColor(AppColors.text)
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.string = isEmpty ? "Translation will appear here...".localized : text

        if isEmpty {
            textView.textColor = .secondaryLabelColor
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.string = isEmpty ? "Translation will appear here...".localized : text
        textView.textColor = isEmpty ? .secondaryLabelColor : .labelColor
    }
}

struct LanguageSelector: View {
    @Binding var selection: Language
    let languages: [Language]
    
    var body: some View {
        Menu {
            ForEach(languages) { language in
                Button(language.displayName) {
                    selection = language
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.displayName).font(.system(size: 12, weight: .medium)).foregroundColor(AppColors.text.opacity(0.6))
            }
        }.menuStyle(.borderlessButton).fixedSize()
    }
}

struct LanguageButton: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(AppColors.text.opacity(0.7)).padding(.horizontal, 8).padding(.vertical, 4).background(AppColors.primary.opacity(0.1)).cornerRadius(4)
    }
}

// VisualEffectView removed (moved to Core/Design)
// Add this component after OutputTextView and before LanguageSelector in TranslationView.swift

struct EditableOutputView: NSViewRepresentable {
    @Binding var text: String
    let originalText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = YisiScrollView()
        scrollView.verticalScroller?.controlSize = .mini

        let textView = NSTextView()
        textView.autoresizingMask = [.width, .height]
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true

        textView.font = AppFont.shared.font

        textView.textColor = .labelColor
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.string = text
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
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        
        init(text: Binding<String>) {
            _text = text
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}



struct CloseButton: View {
    let action: () -> Void
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium)) // Slightly larger for better clickability
                .foregroundColor(AppColors.text.opacity(0.6))
                .opacity(isHovering ? 1.0 : 0.4) // Ghostly when idle, solid when hovered
                .scaleEffect(isHovering ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
                .frame(width: 24, height: 24) // Touch target remains accessible
                .contentShape(Rectangle()) // Ensure the whole frame is clickable
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// A custom text field that looks like a blank line in a sentence


struct YisiButton: View {
    let isLoading: Bool
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppColors.primary.opacity(isLoading ? 0.1 : 1.0))
                    .animation(.easeInOut(duration: 0.3), value: isLoading)
                
                // Text "Yisi"
                Text("Yisi")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundColor(isLoading ? AppColors.primary : AppColors.onAccent)
                    // Breathing Animation
                    .opacity(isLoading ? 0.5 : 1)
                    .scaleEffect(isLoading ? 0.95 : 1)
                    .animation(isLoading ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isLoading)
            }
            .frame(width: 60, height: 28)
            .shadow(color: Color.black.opacity(isHovering && !isLoading ? 0.1 : 0), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct NarrativeTextField: View {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String
    
    var body: some View {
        DynamicHeightTextEditor(
            text: $text,
            height: $height,
            placeholder: placeholder,
            font: AppFont.shared.font
        )
        .frame(height: height)
    }
}

struct AppFont {
    static let shared = AppFont()
    let font: NSFont
    
    private init() {
        let descriptor = NSFont.systemFont(ofSize: 16, weight: .light).fontDescriptor.withDesign(.serif)
        if let descriptor = descriptor {
            self.font = NSFont(descriptor: descriptor, size: 16) ?? .systemFont(ofSize: 16, weight: .light)
        } else {
            self.font = .systemFont(ofSize: 16, weight: .light)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    
    func makeNSView(context: Context) -> NSView {
        let view = WindowAccessorView()
        view.onWindowChange = { [weak view] in
            self.window = view?.window
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class WindowAccessorView: NSView {
        var onWindowChange: (() -> Void)?
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?()
        }
    }
}

// MARK: - Smart Improvement Button

struct SmartImprovementButton: View {
    let hasChanges: Bool
    let isLoading: Bool
    let showSuccess: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            if hasChanges && !isLoading && !showSuccess {
                action()
            }
        }) {
            ZStack {
                if isLoading {
                    // Loading state
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else if showSuccess {
                    // Success state (brand color checkmark)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppColors.primary)
                } else {
                    // Default or Active state
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(hasChanges ? AppColors.primary : .secondary.opacity(0.4))
                }
            }
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(hasChanges && !showSuccess ? AppColors.primary.opacity(0.1) : Color.primary.opacity(0.05))
            )
            .overlay(
                Circle()
                    .stroke(hasChanges && !showSuccess ? AppColors.primary.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasChanges || isLoading)
        .help(hasChanges ? "Analyze your edits and learn".localized : "Edit the translation to enable".localized)
        .animation(.easeInOut(duration: 0.2), value: hasChanges)
        .animation(.easeInOut(duration: 0.2), value: showSuccess)
    }
}
