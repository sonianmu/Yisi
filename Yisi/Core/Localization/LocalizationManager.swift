import SwiftUI
import Combine

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @AppStorage(AppDefaults.Keys.appLanguage) var language: String = AppDefaults.appLanguage {
        didSet {
            objectWillChange.send()
        }
    }
    
    private init() {}
    
    func localized(_ key: String) -> String {
        let dict = language == "zh" ? zhStrings : enStrings
        return dict[key] ?? key
    }
    
    private let enStrings: [String: String] = [
        // General
        "Settings": "Settings",
        "History": "History",
        "General": "General",
        "Prompts": "Prompts",
        "Shortcuts": "Shortcuts",
        "About": "About",
        "Quit": "Quit",
        "Home": "Home",
        "GitHub": "GitHub",
        "还可以做得更好": "Always room for improvement.",
        
        // API
        "AI Service": "AI Service",
        "API Service (Image)": "API Service (Image)",
        "Provider": "Provider",
        "API Key": "API Key",
        "Model": "Model",
        
        // Behavior
        "Behavior": "Behavior",
        "Close Mode": "Close Mode",
        "Click Outside": "Click Outside",
        "X Button": "X Button",
        "Esc Key": "Esc Key",
        "Layout": "Layout",
        "Customize Popup Layout": "Customize Popup Layout",
        "Drag the window to position it. Drag the corner to resize.": "Drag the window to position it. Drag the corner to resize.",
        "Cancel": "Cancel",
        "Save": "Save",
        
        // Language & Appearance
        "Language": "Language",
        "Appearance": "Appearance",
        "System": "System",
        "Light": "Light",
        "Dark": "Dark",
        "English": "English",
        "Simplified Chinese": "Simplified Chinese",
        
        // Default Path
        "Default Path": "Default Translation Path",
        "Source": "Source",
        "Target": "Target",
        
        // Image Mode
        "Image": "Image",
        "Image Mode": "Image Mode",
        "System OCR": "System OCR",
        "AI Vision": "AI Vision",
        "Only recognizes pure text structures in images": "Only recognizes pure text structures in images",
        "Same API": "Same API",
        "Apply to Image Mode": "Apply to image mode",
        "Apply text settings to image mode": "Apply text settings to image mode",
        "This provider does not support image mode": "This provider does not support image mode",
        "Screenshot": "Screenshot",
        "Click to upload image": "Click to upload image",
        "or drag & drop": "or drag & drop",
        "Recognizing image...": "Recognizing image...",
        "AI recognition result will appear here...": "AI recognition result will appear here...",
        "Select an image to recognize": "Select an image to recognize",
        "Select": "Select",
        
        // Screenshot Overlay HUD
        "Drag to select · Double-click to upload · Right-click to cancel": "Drag to select · Double-click to upload · Right-click to cancel",
        
        // Prompts
        "Customize the system prompts used for translation.": "Customize the system prompts used for translation.",
        "Coming soon": "Coming soon",
        "Modes": "Modes",
        
        // Preset Mode
        "启用预设模式": "Enable Preset Mode",
        "Enable Preset Mode": "Enable Preset Mode",
        "关闭时为临时自定义模式；开启后选择预设": "Off: Temporary custom mode; On: Select preset",
        "Use saved presets instead of custom mode": "Use saved presets instead of custom mode",
        "选择预设": "Select Preset",
        "Select Preset": "Select Preset",
        "默认翻译": "Default Translation",
        "Default Translation": "Default Translation",
        "自定义预设": "Custom Presets",
        "Custom Presets": "Custom Presets",
        "暂无自定义预设": "No custom presets yet",
        "No custom presets yet": "No custom presets yet",
        "New Preset": "New Preset",
        "Edit Preset": "Edit Preset",
        "Name": "Name",
        "e.g. Code Audit": "e.g. Code Audit",
        "Input Perception": "Input Perception",
        "Output Instruction": "Output Instruction",
        
        // Custom Prompt Area
        "I perceive this as": "I perceive this as",
        "please": "please",
        "Ancient Poetry": "Ancient Poetry",
        "translate to modern English": "translate to modern English",
        
        // Deep Thinking
        "Thinking": "Thinking",
        "Enable deep reasoning for AI": "May increase wait time and token usage",
        "Advanced": "Advanced",
        
        // Learned Rules
        "Learned Rules": "Learned Rules",
        
        // Shortcuts
        "Activate": "Activate",
        "Record Shortcut": "Record Shortcut",
        "Press keys...": "Press keys...",
        "Requires Cmd/Ctrl/Opt": "Requires Cmd/Ctrl/Opt",
        "Press the key combination you want to use to activate Yisi.": "Press the key combination you want to use to activate Yisi.",
        "Press the key combination you want to use.": "Press the key combination you want to use.",
        
        // History
        "No History": "No History",
        "Your recent translations will appear here.": "Your recent translations will appear here.",
        "All": "All",
        "Today": "Today",
        "Yesterday": "Yesterday",
        "This Week": "This Week",
        "Older": "Older",
        
        // Translation View
        "Type or paste text..": "Type or paste text..",
        "Type or paste text...": "Type or paste text...",
        "Translation will appear here...": "Translation will appear here...",
        "Translation result will appear here...": "Translation result will appear here...",
        "翻译结果将显示在这里...": "Translation will appear here...",
        "处理结果将显示在这里...": "Processing result will appear here...",
        "输出结果将显示在这里...": "Output will appear here...",
        "Translate": "Translate",
        "Swap languages": "Swap languages",
        "Open Settings": "Open Settings",
        "Accessibility permission required to capture text.": "Accessibility permission required to capture text.",
        "Language pack required for offline translation.": "Language pack required for offline translation.",
        "Download": "Download",
        "Auto Detect": "Auto Detect",
        "Traditional Chinese": "Traditional Chinese",
        "Japanese": "Japanese",
        "Korean": "Korean",
        "French": "French",
        "Spanish": "Spanish",
        "German": "German",
        "Russian": "Russian",
        "Arabic": "Arabic",
        "Thai": "Thai",
        "Vietnamese": "Vietnamese",
        
        // Settings - Translation
        "Engine": "Engine",
        "Improve": "Improve",
        "Smart Improve": "Smart Improve",
        "Enable translation improvement": "Edit translations and generate personalized learning rules",
        "Analyze your edits and learn": "Analyze your edits and learn",
        "Edit the translation to enable": "Edit the translation to enable",
        
        // History additional
        "Load More": "Load More",
        "View Image": "View Image",
        "%d days ago": "%d days ago",
        "Clear All": "Clear All",
        "Clear History": "Clear History",
        "Clear": "Clear",
        "Are you sure you want to delete all history items? This action cannot be undone.": "Are you sure you want to delete all history items? This action cannot be undone.",
        "No matches found": "No matches found",
        "Vision": "Vision",
        "Translation": "Translation",
        "Preset": "Preset",
        "Custom": "Custom",
        
        // Preset description
        "Standard translation mode, supports Learned Rules": "Standard translation mode, supports Learned Rules",
        
        // Learned Rules content
        "Translation rules learned from your corrections.": "Translation rules learned from your corrections.",
        "No rules learned yet": "No rules learned yet",
        "Edit translations and click Improve to start learning.": "Edit translations and click Improve to start learning.",
        
        // Missing keys
        "macOS System": "macOS System",
        "Copied to clipboard": "Copied to clipboard",
        
        // System Translation
        "System Translation": "System Translation",
        "Requires macOS 15.0 or later.": "Requires macOS 15.0 or later.",
        "macOS built-in translation. Fast, private, requires language pack.": "macOS built-in translation. Fast, private, requires language pack.",
        "Language Packs": "Language Packs",
        "Checking...": "Checking...",
        "Download for offline translation.": "Download for offline translation.",
        
        // Engine
        "AI Translation": "AI Translation",
        

        // Settings - Translation (Extra)
        "Learn from your corrections": "Learn from your corrections",
        "Text mode only. Images excluded to save space.": "Text mode only",
        "Standard translation mode": "Standard translation mode",
        
        // Prompts (Extra)
        "How AI should understand the input...": "How AI should understand the input...",
        "How AI should format the output...": "How AI should format the output...",
        
        // Launch at Login
        "Auto Start": "Auto Start",

        // Welcome / Permissions
        "Permissions Required": "Permissions Required",
        "Accessibility": "Accessibility",
        "Global hotkeys & text capture": "Global hotkeys & text capture",
        "Screen Recording": "Screen Recording",
        "Screenshot translation": "Screenshot translation",
        "Enable Yisi in System Settings. If it is missing, reveal the app in Finder and add it with the + button.": "Enable Yisi in System Settings. If it is missing, reveal the app in Finder and add it with the + button.",
        "Show App in Finder": "Show App in Finder",
        "Waiting for authorization…": "Waiting for authorization…",
        "Enable": "Enable",
        "Get Started": "Get Started",
        "Skip": "Skip",
        "Next": "Next",
        "Granted": "Granted",
        "Open System Settings": "Open System Settings",
        "Optional. You can set this up later in Settings.": "Optional. You can set this up later in Settings.",
        "Grant access to enable core features": "Grant access to enable core features",
        "Required": "Required",
        "Requires restart after enabling": "Requires restart after enabling",
        "Enable Accessibility to continue": "Enable Accessibility to continue",
        "有Yisi，才有意思。": "With Yisi, everything gets interesting.",
        "Begin": "Begin",

        // Updates
        "Auto Update": "Auto Update",
        "Check for Updates": "Check for Updates",
        "Update Available": "Update Available",
        "Current Version": "Current Version",
        "A new version %@ is available. Current version: %@": "A new version %@ is available. Current version: %@",
        "You're up to date": "You're up to date",
        "Yisi %@ is the latest version.": "Yisi %@ is the latest version.",
        "Later": "Later",
        "Update Now": "Update Now",
        "Update Failed": "Update Failed",
        "Auto update failed. You can download manually from GitHub.": "Auto update failed. You can download manually from GitHub.",
        "Downloading...": "Downloading...",
        "Installing...": "Installing...",
        "Restarting...": "Restarting..."
    ]
    
    private let zhStrings: [String: String] = [
        "This model is not configured for image input": "当前模型未配置图片输入能力",
        "Temperature During Reasoning": "推理时发送温度",
        "API key not saved. Save it before using this service.": "密钥尚未保存，使用服务前请点击保存。",
        "Custom Service": "自定义服务",
        "Protocol": "接口协议",
        "OpenAI Compatible": "OpenAI 兼容",
        "Gemini Native": "Gemini 原生",
        "Anthropic Messages": "Anthropic Messages",
        "Base URL": "服务地址",
        "Use the API base path, including /v1 or /v1beta when required.": "填写 API 基础路径，按服务要求包含 /v1 或 /v1beta。",
        "Optional for local services": "本地服务可留空",
        "Save API Key": "保存密钥",
        "API key saved to Keychain.": "密钥已保存到系统钥匙串。",
        "Could not save the API key to Keychain.": "无法将密钥保存到系统钥匙串。",
        "Enter any model ID": "填写模型 ID",
        "Advanced Adaptation": "高级适配",
        "Reasoning Control": "推理控制",
        "Service Default": "跟随服务默认",
        "No Native Reasoning": "无原生推理",
        "Always On": "始终推理",
        "Reasoning Effort": "推理强度",
        "Thinking Type": "思考类型开关",
        "Enable Thinking": "思考布尔开关",
        "Gemini Thinking Budget": "Gemini 思考预算",
        "Gemini Thinking Level": "Gemini 思考等级",
        "Anthropic Thinking Budget": "Anthropic 思考预算",
        "Anthropic Adaptive Thinking": "Anthropic 自适应思考",
        "Enabled Value": "开启时的值",
        "Disabled Value": "关闭时的值",
        "Thinking Budget": "思考预算",
        "Minimum Budget": "最低思考预算",
        "Image Support": "支持图片输入",
        "Temperature": "发送温度参数",
        "Native JSON Mode": "原生 JSON 模式",
        "Token Parameter": "Token 参数",
        "Output Token Limit": "输出 Token 上限",
        "Use values supported by this model. Low effort still enables reasoning.": "请填写模型支持的参数值；低强度仍会进行推理。",
        "Capabilities are saved for this model. Unknown models follow service defaults.": "能力配置按模型保存；未知模型跟随服务默认。",
        "Test Connection": "测试连接",
        "Sends a small test request using the current thinking preference.": "按当前思考偏好发送少量测试内容。",
        "Connection and result JSON verified.": "连接和结果 JSON 验证通过。",
        "Connected, but the model did not return the expected result JSON.": "已连接，但模型未返回预期的结果 JSON。",
        "Reasoning follows the service default. Configure capabilities to control it.": "推理跟随服务默认；配置模型能力后可控制推理。",
        "No native reasoning. Deep thinking adds a translation quality check.": "无原生推理；开启深度思考会加强默认翻译的质量检查。",
        "This model always reasons; the switch cannot disable it.": "该模型始终推理，此开关无法关闭原生推理。",
        "Deep thinking switches native reasoning on or off.": "此开关会开启或关闭原生推理。",
        "Turning off deep thinking uses the configured lower effort; reasoning remains enabled.": "关闭时使用配置的较低强度，原生推理仍然开启。",
        "This model cannot disable reasoning; turning it off uses the minimum budget.": "此模型无法关闭推理；关闭时使用最低思考预算。",
        "Deep Thinking Preference": "深度思考",
        "Prefer deeper reasoning; behavior depends on model capabilities": "优先深度思考，实际行为取决于模型能力",
        "Enter a model ID.": "请填写模型 ID。",
        "This model is not configured for images. Enable image support or choose System OCR.": "当前模型未配置图片能力，请开启图片支持或选择系统 OCR。",
        "Output token limit must be between 1 and 1000000.": "输出 Token 上限须在 1 到 1000000 之间。",
        "The reasoning control does not match the selected protocol.": "推理控制方式与所选接口协议不匹配。",
        "Enter a valid HTTP or HTTPS base URL without credentials, query or fragment.": "请填写有效的 HTTP 或 HTTPS 服务地址，不包含账号、查询参数或锚点。",
        "Invalid service URL.": "服务地址无效。",
        "Thinking budget must be non-negative and below the output token limit.": "思考预算须为非负数且小于输出 Token 上限。",
        "Anthropic thinking budget must be at least 1024 and below the output token limit.": "Anthropic 思考预算须至少为 1024 且小于输出 Token 上限。",
        "Enter both the enabled and disabled reasoning values.": "请填写开启和关闭时的推理参数值。",
        "The service returned an invalid response.": "服务返回了无效响应。",
        "The service returned no final answer.": "服务未返回最终结果。",
        "The response reached the output limit. Increase the token limit in Advanced Adaptation.": "响应达到输出上限，请在高级适配中增大 Token 上限。",
        "Failed to encode image.": "图片编码失败。",

        // General
        "Settings": "设置",
        "Test and Save": "测试并保存",
        "Enter an API key.": "请输入 API 密钥。",
        "Enter the API base URL.": "请输入 API 服务地址。",
        "Connection successful. Settings saved.": "连接成功，配置已保存。",
        "Test failed. Previous settings were kept.": "测试失败，原配置未更改。",
        "No AI service is configured. Configure an AI service or switch to the System Translation engine in Translation settings.": "当前没有配置 AI 服务，请配置 AI 服务，或在“翻译”设置中将引擎切换为系统翻译。",
        "Still not working after repair? Please report it on GitHub Issues.": "修复后仍无法使用，请前往 GitHub Issues 反馈。",
        "Select. Translate. Keep your flow.": "选中，即刻呈现。",
        "Translate selected text or screenshots, without leaving what you are doing.": "翻译选中文字与截图，让灵感和工作继续。",
        "Enter your API key and model, then test and save. You can also configure this later in Settings.": "填写 API 密钥和模型后，点击测试并保存。也可以稍后在设置中配置。",
        "Set up later": "稍后配置",
        "You are ready.": "一切就绪。",
        "Yisi is in your menu bar. Select text or take a screenshot to begin.": "Yisi 已在菜单栏等候。选中文字，或截取画面，即可开始。",
        "Repair Software": "软件修复",
        "Repair and Restart": "修复并重新启动",
        "Repairing…": "正在修复…",
        "Restart": "重新启动",
        "GitHub Issues": "GitHub Issues",
        "Restore normal operation while preserving API keys, service settings and translation history.": "尝试恢复正常运行，保留 API 密钥、服务配置和翻译历史。",
        "Still not working after repair? Please report it on GitHub Issues. Do not include API keys or private translation content.": "修复后仍无法使用？请前往 GitHub Issues 反馈，请勿提交 API 密钥或私人翻译内容。",
        "Repair restores appearance, shortcuts and window layout, archives caches, and attempts to recover unavailable permissions. API keys, service settings, translation history, history images, presets and learned rules are preserved. Settings are backed up first, but some temporary data or personal preferences may be lost. Yisi will restart. If it still does not work, please report the problem on GitHub Issues.": "修复将恢复外观、快捷键和窗口布局，备份并清理缓存，尝试恢复失效的系统授权。\n\nAPI 密钥、服务配置、翻译历史、历史截图、预设和学习规则将保留。我们会先备份设置并尽最大可能保留数据，但仍可能丢失部分临时数据或个性化设置。\n\n修复后 Yisi 将重新启动。若仍无法使用，请前往 GitHub Issues 反馈。",
        "Repair requires launching the installed Yisi app.": "请通过 Yisi.app 启动应用后再运行修复。",
        "Could not save repaired settings. The backup has been retained.": "无法保存修复后的设置，备份已保留。",
        "Could not save the restart state. The backup has been retained.": "无法保存重启状态，备份已保留。",
        "System authorization still required": "仍需完成系统授权",
        "Settings and caches have been repaired. Some permissions could not be reset automatically; after restart, follow the authorization prompts. If the problem persists, please report it on GitHub Issues.": "设置和缓存已修复，但部分权限未能自动重置。重启后请按提示完成授权；若问题仍存在，请前往 GitHub Issues 反馈。",
        "Repair could not finish": "修复未能完成",
        "Your API keys and history have not been deleted. Please report the problem on GitHub Issues if it persists.": "API 密钥和翻译历史没有被删除。若问题仍存在，请前往 GitHub Issues 反馈。",
        "History": "历史记录",
        "General": "通用",
        "Prompts": "提示词",
        "Shortcuts": "快捷键",
        "About": "关于",
        "Quit": "退出",
        "Home": "主页",
        "GitHub": "GitHub",
        "还可以做得更好": "还可以做得更好",
        
        // API
        "AI Service": "AI 服务",
        "API Service (Image)": "API 服务（图片）",
        "Provider": "提供商",
        "API Key": "API 密钥",
        "Model": "模型",
        
        // Behavior
        "Behavior": "行为",
        "Close Mode": "关闭方式",
        "Click Outside": "点击外部",
        "X Button": "关闭按钮",
        "Esc Key": "Esc 键",
        "Layout": "布局",
        "Customize Popup Layout": "自定义弹窗布局",
        "Drag the window to position it. Drag the corner to resize.": "拖动窗口以调整位置。拖动角落以调整大小。",
        "Cancel": "取消",
        "Save": "保存",
        
        // Language & Appearance
        "Language": "语言",
        "Appearance": "外观",
        "System": "跟随系统",
        "Light": "浅色",
        "Dark": "深色",
        "English": "英语",
        "Simplified Chinese": "简体中文",
        
        // Default Path
        "Default Path": "默认翻译路径",
        "Source": "源语言",
        "Target": "目标语言",
        
        // Image Mode
        "Image": "图片",
        "Image Mode": "图片模式",
        "System OCR": "系统 OCR",
        "AI Vision": "AI 视觉",
        "Only recognizes pure text structures in images": "仅识别图像中的纯文字结构",
        "Same API": "保持一致",
        "Apply to Image Mode": "应用于图片模式",
        "Apply text settings to image mode": "应用文本模式的配置",
        "This provider does not support image mode": "当前服务商不支持图片模式",
        "Screenshot": "截图",
        "Click to upload image": "点击上传图片",
        "or drag & drop": "或拖放图片",
        "Recognizing image...": "正在识别图片...",
        "AI recognition result will appear here...": "AI 识别结果将显示在这里...",
        "Select an image to recognize": "选择要识别的图片",
        "Select": "选择",
        
        // Screenshot Overlay HUD
        "Drag to select · Double-click to upload · Right-click to cancel": "拖拽选区 · 双击上传 · 右键取消",
        
        // Prompts
        "Customize the system prompts used for translation.": "自定义用于翻译的系统提示词。",
        "Coming soon": "即将推出",
        "Modes": "模式",
        
        // Preset Mode
        "启用预设模式": "启用预设模式",
        "Enable Preset Mode": "启用预设模式",
        "关闭时为临时自定义模式；开启后选择预设": "关闭时为临时自定义模式；开启后选择预设",
        "Use saved presets instead of custom mode": "使用保存的预设而非自定义模式",
        "选择预设": "选择预设", 
        "Select Preset": "选择预设",
        "默认翻译": "默认翻译",
        "Default Translation": "默认翻译",
        "自定义预设": "自定义预设",
        "Custom Presets": "自定义预设",
        "暂无自定义预设": "暂无自定义预设",
        "No custom presets yet": "暂无自定义预设",
        "New Preset": "新建预设",
        "Edit Preset": "编辑预设",
        "Name": "名称",
        "e.g. Code Audit": "例如：代码审计",
        "Input Perception": "输入感知",
        "Output Instruction": "输出指令",
        
        // Custom Prompt Area
        "I perceive this as": "这是",
        "please": "请",
        "Ancient Poetry": "古诗词",
        "translate to modern English": "翻译成现代中文",
        
        // Deep Thinking
        "Thinking": "深度思考",
        "Enable deep reasoning for AI": "可能会增加等待时间和 Token 消耗",
        "Advanced": "高级",
        
        // Learned Rules (keep as English term)
        "Learned Rules": "Learned Rules",
        
        // Shortcuts
        "Activate": "激活",
        "Record Shortcut": "录制快捷键",
        "Press keys...": "按下按键...",
        "Requires Cmd/Ctrl/Opt": "需要 Cmd/Ctrl/Opt 修饰键",
        "Press the key combination you want to use to activate Yisi.": "按下您想要用于激活 Yisi 的组合键。",
        "Press the key combination you want to use.": "按下您想要使用的组合键。",
        
        // History
        "No History": "暂无历史",
        "Your recent translations will appear here.": "您最近的翻译将显示在这里。",
        "All": "全部",
        "Today": "今天",
        "Yesterday": "昨天",
        "This Week": "本周",
        "Older": "更早",
        
        // Translation View
        "Type or paste text..": "输入或粘贴文本..",
        "Type or paste text...": "输入或粘贴文本...",
        "Translation will appear here...": "翻译结果将显示在这里...",
        "Translation result will appear here...": "翻译结果将显示在这里...",
        "翻译结果将显示在这里...": "翻译结果将显示在这里...",
        "处理结果将显示在这里...": "处理结果将显示在这里...",
        "输出结果将显示在这里...": "输出结果将显示在这里...",
        "Translate": "翻译",
        "Swap languages": "交换语言",
        "Open Settings": "打开设置",
        "Accessibility permission required to capture text.": "需要辅助功能权限以捕获文本。",
        "Language pack required for offline translation.": "离线翻译需要语言包支持。",
        "Download": "下载",
        "Auto Detect": "自动检测",
        "Traditional Chinese": "繁体中文",
        "Japanese": "日语",
        "Korean": "韩语",
        "French": "法语",
        "Spanish": "西班牙语",
        "German": "德语",
        "Russian": "俄语",
        "Arabic": "阿拉伯语",
        "Thai": "泰语",
        "Vietnamese": "越南语",
        
        // Settings - Translation  
        "Engine": "引擎",
        "Improve": "智能优化",
        "Smart Improve": "智能优化",
        "Enable translation improvement": "支持编辑译文并生成个性化学习规则",
        "Analyze your edits and learn": "分析您的修改并学习",
        "Edit the translation to enable": "编辑译文以启用",
        
        // History additional
        "Load More": "加载更多",
        "View Image": "查看图片",
        "%d days ago": "%d 天前",
        "Clear All": "清空全部",
        "Clear History": "清空历史",
        "Clear": "清空",
        "Are you sure you want to delete all history items? This action cannot be undone.": "确定要删除所有历史记录吗？此操作无法撤销。",
        "No matches found": "未找到匹配项",
        "Vision": "视觉",
        "Translation": "翻译",
        "Preset": "预设",
        "Custom": "自定义",
        
        // Preset description
        "Standard translation mode, supports Learned Rules": "标准翻译模式，支持 Learned Rules",
        
        // Learned Rules content
        "Translation rules learned from your corrections.": "从您的修正中学习到的翻译规则。",
        "No rules learned yet": "尚未学习到规则",
        "Edit translations and click Improve to start learning.": "编辑译文并点击智能优化开始学习。",
        
        // Missing keys
        "macOS System": "macOS 系统",
        "Copied to clipboard": "已复制到剪贴板",
        
        // System Translation
        "System Translation": "系统翻译",
        "Requires macOS 15.0 or later.": "需要 macOS 15.0 或更高版本。",
        "macOS built-in translation. Fast, private, requires language pack.": "macOS 内置翻译，快速隐私，需下载语言包",
        "Language Packs": "语言包",
        "Checking...": "正在检查...",
        "Download for offline translation.": "下载以通过系统进行离线翻译。",
        
        // Engine
        "AI Translation": "AI 翻译",
        

        // Settings - Translation (Extra)
        "Learn from your corrections": "从您的修正中学习",
        "Text mode only. Images excluded to save space.": "仅限文本模式",
        "Standard translation mode": "标准翻译模式",
        
        // Prompts (Extra)
        "How AI should understand the input...": "AI 应如何理解输入...",
        "How AI should format the output...": "AI 应如何格式化输出...",
        
        // Launch at Login
        "Auto Start": "开机自启",

        // Welcome / Permissions
        "Permissions Required": "需要权限",
        "Accessibility": "辅助功能",
        "Global hotkeys & text capture": "全局快捷键和文本捕获",
        "Screen Recording": "屏幕录制",
        "Screenshot translation": "截图翻译",
        "Enable Yisi in System Settings. If it is missing, reveal the app in Finder and add it with the + button.": "请在系统设置中开启 Yisi。若列表里没有它，可在 Finder 中显示 App，再通过 + 按钮添加。",
        "Show App in Finder": "在 Finder 中显示 App",
        "Waiting for authorization…": "等待系统授权…",
        "Enable": "开启",
        "Get Started": "开始使用",
        "Skip": "跳过",
        "Next": "下一步",
        "Granted": "已授权",
        "Open System Settings": "打开系统设置",
        "Optional. You can set this up later in Settings.": "可选项，稍后可在设置中配置。",
        "Grant access to enable core features": "授权以启用核心功能",
        "Required": "必需",
        "Requires restart after enabling": "启用后需重启应用",
        "Enable Accessibility to continue": "请先开启辅助功能",
        "有Yisi，才有意思。": "有Yisi，才有意思。",
        "Begin": "开始",

        // Updates
        "Auto Update": "自动更新",
        "Check for Updates": "检查更新",
        "Update Available": "发现新版本",
        "Current Version": "当前版本",
        "A new version %@ is available. Current version: %@": "新版本 %@ 已发布，当前版本：%@",
        "You're up to date": "已是最新版本",
        "Yisi %@ is the latest version.": "Yisi %@ 已是最新版本。",
        "Later": "稍后",
        "Update Now": "立即更新",
        "Update Failed": "更新失败",
        "Auto update failed. You can download manually from GitHub.": "自动更新失败，您可以前往 GitHub 手动下载。",
        "Downloading...": "正在下载...",
        "Installing...": "正在安装...",
        "Restarting...": "正在重启..."
    ]
}

extension String {
    var localized: String {
        LocalizationManager.shared.localized(self)
    }
}
