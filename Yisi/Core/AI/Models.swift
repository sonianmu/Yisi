import Foundation

struct TranslationResponse: Codable {
    let detected_type: String
    let thinking_process: String?  // 兼容旧响应；新的 Prompt 不要求输出分析过程
    let translation_result: String
}

enum PromptMode: Equatable {
    case temporaryCustom        // 预设关闭，弹窗显示自定义输入框
    case defaultTranslation     // 预设开启 + 选择"默认翻译"，显示语言选择器，Learned Rules 生效
    case userPreset(PromptPreset)  // 预设开启 + 选择用户预设，弹窗最简洁
    
    static func == (lhs: PromptMode, rhs: PromptMode) -> Bool {
        switch (lhs, rhs) {
        case (.temporaryCustom, .temporaryCustom):
            return true
        case (.defaultTranslation, .defaultTranslation):
            return true
        case (.userPreset(let lhsPreset), .userPreset(let rhsPreset)):
            return lhsPreset.id == rhsPreset.id
        default:
            return false
        }
    }
}

struct PromptPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var inputPerception: String
    var outputInstruction: String
}
