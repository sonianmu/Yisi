import Foundation

/// PromptCoordinator: 提示词协调器
/// 职责：
/// - 根据当前模式选择合适的 Builder
/// - 统一的入口点，简化调用方逻辑
/// - 清晰的职责分离
class PromptCoordinator {
    
    // MARK: - Builders
    
    private let translationBuilder = TranslationPromptBuilder()
    private let presetBuilder = PresetPromptBuilder()
    private let customBuilder = CustomPromptBuilder()
    
    // MARK: - Singleton
    
    static let shared = PromptCoordinator()
    private init() {}
    
    // MARK: - Public Interface
    
    /// 根据模式生成对应的系统提示词（统一 Pipeline）
    /// - Parameters:
    ///   - mode: 提示词模式（翻译/预设/临时自定义）
    ///   - withLearnedRules: 是否包含用户纠正的学习规则
    ///   - hasImage: 是否为图片输入（仅翻译模式使用）
    ///   - enhanceReview: 是否加强翻译检查（仅确认无原生推理的翻译模型）
    ///   - sourceLanguage: 源语言（图片模式需要）
    ///   - targetLanguage: 目标语言（图片模式需要）
    /// - Returns: 完整的系统提示词
    func generateSystemPrompt(
        for mode: PromptMode,
        withLearnedRules: Bool = true,
        hasImage: Bool = false,
        enhanceReview: Bool = false,
        sourceLanguage: String = "Auto Detect",
        targetLanguage: String = "简体中文"
    ) -> String {
        switch mode {
        case .defaultTranslation:
            // 翻译模式：使用翻译Builder + Learned Rules（图片/文本统一 Pipeline）
            return translationBuilder.buildSystemPrompt(
                withLearnedRules: withLearnedRules,
                preset: nil,
                hasImage: hasImage,
                enhanceReview: enhanceReview,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
            
        case .userPreset(let preset):
            // 预设模式：使用预设 Builder（不控制 CoT，用户自行处理）
            return presetBuilder.buildSystemPrompt(preset: preset)
            
        case .temporaryCustom:
            // 临时自定义：不控制 CoT，用户自行处理
            return customBuilder.buildSystemPrompt(inputContext: nil, outputRequirement: nil)
        }
    }
    /// 生成临时自定义任务的系统提示词
    /// - Parameters:
    ///   - inputContext: 用户输入的任务理解
    ///   - outputRequirement: 用户期望的输出
    /// - Returns: 完整的系统提示词
    func generateCustomPrompt(inputContext: String?, outputRequirement: String?) -> String {
        return customBuilder.buildSystemPrompt(inputContext: inputContext, outputRequirement: outputRequirement)
    }
    
    /// 生成用户提示词（包含文本和语言信息）
    /// - Parameters:
    ///   - text: 待处理的文本
    ///   - sourceLanguage: 源语言
    ///   - targetLanguage: 目标语言
    ///   - mode: 提示词模式
    /// - Returns: 用户提示词
    func generateUserPrompt(text: String, sourceLanguage: String, targetLanguage: String, mode: PromptMode = .defaultTranslation) -> String {
        // 自定义模式和预设模式：不添加"Translate..."指令，System Prompt 已定义了用户任务
        if case .temporaryCustom = mode {
            return "Input Text:\n\(text)"
        }
        if case .userPreset = mode {
            return "Input Text:\n\(text)"
        }
        
        var prompt = "Translate the following text to \(targetLanguage)."
        if sourceLanguage != "Auto Detect" {
            prompt = "Translate the following text from \(sourceLanguage) to \(targetLanguage)."
        }
        
        prompt += "\n\nInput Text:\n\(text)"
        
        return prompt
    }
    
    // MARK: - Image Prompt Generation
    
    /// 生成图片处理的系统提示词
    /// - Parameters:
    ///   - mode: 提示词模式
    ///   - sourceLanguage: 源语言
    ///   - targetLanguage: 目标语言
    ///   - enhanceReview: 是否加强翻译检查
    ///   - customPerception: 自定义感知（用于自定义模式）
    ///   - customInstruction: 自定义指令（用于自定义模式）
    /// - Returns: 给 AI 的图片处理系统提示词
    func generateImageSystemPrompt(
        mode: PromptMode,
        sourceLanguage: String,
        targetLanguage: String,
        enhanceReview: Bool = false,
        customPerception: String? = nil,
        customInstruction: String? = nil
    ) -> String {
        switch mode {
        case .defaultTranslation:
            // 翻译模式：使用统一 Pipeline（hasImage = true）
            return generateSystemPrompt(
                for: mode,
                withLearnedRules: true,
                hasImage: true,
                enhanceReview: enhanceReview,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
            
        case .temporaryCustom:
            // 自定义模式：使用 CustomBuilder 的图片处理
            return customBuilder.buildImagePrompt(
                inputContext: customPerception,
                outputRequirement: customInstruction
            )
            
        case .userPreset(let preset):
            // 预设模式：使用 PresetBuilder 的图片处理
            return presetBuilder.buildImagePrompt(preset: preset)
        }
    }
}

