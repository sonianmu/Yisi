import Foundation
import AppKit

enum AppDefaults {

    // MARK: - Keys

    enum Keys {
        // General
        static let appTheme = "app_theme"
        static let appLanguage = "app_language"
        static let closeMode = "close_mode"
        static let hasLaunchedBefore = "has_launched_before"
        static let welcomeCompleted = "welcome_completed"
        static let welcomeStep = "welcome_step"
        static let repairPending = "repair_pending"
        static let repairBackupPath = "repair_backup_path"
        static let launchAtLogin = "launch_at_login"
        static let autoCheckUpdates = "auto_check_updates"

        // Translation
        static let translationEngine = "translation_engine"
        static let defaultSourceLanguage = "default_source_language"
        static let defaultTargetLanguage = "default_target_language"
        static let enableImproveFeature = "enable_improve_feature"
        static let presetModeEnabled = "preset_mode_enabled"
        static let selectedPresetId = "selected_preset_id"
        static let savedPresets = "saved_presets"

        // AI Service - Text
        static let apiProvider = "api_provider"
        static let geminiApiKey = "gemini_api_key"
        static let geminiModel = "gemini_model"
        static let openaiApiKey = "openai_api_key"
        static let openaiModel = "openai_model"
        static let zhipuApiKey = "zhipu_api_key"
        static let zhipuModel = "zhipu_model"
        static let minimaxApiKey = "minimax_api_key"
        static let minimaxModel = "minimax_model"
        static let deepseekApiKey = "deepseek_api_key"
        static let deepseekModel = "deepseek_model"
        static let enableDeepThinking = "enable_deep_thinking"

        // AI Service - Image
        static let imageProcessingStrategy = "image_processing_strategy"
        static let applyApiToImageMode = "apply_api_to_image_mode"
        static let imageApiProvider = "image_api_provider"
        static let imageGeminiApiKey = "image_gemini_api_key"
        static let imageGeminiModel = "image_gemini_model"
        static let imageOpenaiApiKey = "image_openai_api_key"
        static let imageOpenaiModel = "image_openai_model"
        static let imageZhipuApiKey = "image_zhipu_api_key"
        static let imageZhipuModel = "image_zhipu_model"

        // Shortcuts
        static let globalShortcutKey = "global_shortcut_key"
        static let globalShortcutModifiers = "global_shortcut_modifiers"
        static let screenshotShortcutKey = "screenshot_shortcut_key"
        static let screenshotShortcutModifiers = "screenshot_shortcut_modifiers"

        // Window
        static let popupFrameRect = "popup_frame_rect"
    }

    // MARK: - Default Values

    // General
    static let appTheme = "light"
    static let appLanguage = "zh"
    static let closeMode = "clickOutside"
    static let launchAtLogin = true
    static let autoCheckUpdates = true

    // Translation
    static let translationEngine = "ai"
    static let defaultSourceLanguage = "Auto Detect"
    static let defaultTargetLanguage = "Simplified Chinese"
    static let enableImproveFeature = false
    static let presetModeEnabled = true
    static let selectedPresetId = "default_translation"

    // AI Service - Text
    static let apiProvider = "Zhipu AI"
    static let geminiModel = ""
    static let openaiModel = ""
    static let zhipuModel = ""
    static let minimaxModel = ""
    static let deepseekModel = ""
    static let enableDeepThinking = false

    // AI Service - Image
    static let imageProcessingStrategy = "ai_vision"
    static let applyApiToImageMode = false
    static let imageApiProvider = "Zhipu AI"
    static let imageGeminiModel = ""
    static let imageOpenaiModel = ""
    static let imageZhipuModel = ""

    // Shortcuts
    static let globalShortcutKeyCode: UInt16 = 16    // Y
    static let globalShortcutMods: NSEvent.ModifierFlags = [.command, .control]
    static let screenshotShortcutKeyCode: UInt16 = 7  // X
    static let screenshotShortcutMods: NSEvent.ModifierFlags = [.command, .shift]

    // Window
    static let popupWindowWidth: CGFloat = 600
    static let popupWindowHeight: CGFloat = 330
    static let settingsWindowWidth: CGFloat = 550
    static let settingsWindowHeight: CGFloat = 420

    // MARK: - Registration

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.appTheme: appTheme,
            Keys.appLanguage: appLanguage,
            Keys.closeMode: closeMode,
            Keys.launchAtLogin: launchAtLogin,
            Keys.autoCheckUpdates: autoCheckUpdates,
            Keys.translationEngine: translationEngine,
            Keys.defaultSourceLanguage: defaultSourceLanguage,
            Keys.defaultTargetLanguage: defaultTargetLanguage,
            Keys.enableImproveFeature: enableImproveFeature,
            Keys.presetModeEnabled: presetModeEnabled,
            Keys.selectedPresetId: selectedPresetId,
            Keys.apiProvider: apiProvider,
            Keys.geminiModel: geminiModel,
            Keys.openaiModel: openaiModel,
            Keys.zhipuModel: zhipuModel,
            Keys.minimaxModel: minimaxModel,
            Keys.deepseekModel: deepseekModel,
            Keys.enableDeepThinking: enableDeepThinking,
            Keys.imageProcessingStrategy: imageProcessingStrategy,
            Keys.applyApiToImageMode: applyApiToImageMode,
            Keys.imageApiProvider: imageApiProvider,
            Keys.imageGeminiModel: imageGeminiModel,
            Keys.imageOpenaiModel: imageOpenaiModel,
            Keys.imageZhipuModel: imageZhipuModel,
        ])
    }
}
