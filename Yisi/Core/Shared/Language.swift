import Foundation

enum Language: String, CaseIterable, Identifiable {
    case auto = "Auto Detect"
    case english = "English"
    case simplifiedChinese = "Simplified Chinese"
    case traditionalChinese = "Traditional Chinese"
    case japanese = "Japanese"
    case korean = "Korean"
    case french = "French"
    case spanish = "Spanish"
    case german = "German"
    case russian = "Russian"
    case arabic = "Arabic"
    case thai = "Thai"
    case vietnamese = "Vietnamese"
    
    var displayName: String {
        return self.rawValue.localized
    }
    
    var id: String { self.rawValue }
    
    /// BCP 47 code shared by system translation, translators and modules. Auto Detect is "auto".
    var code: String {
        switch self {
        case .auto: return "auto"
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .spanish: return "es"
        case .german: return "de"
        case .russian: return "ru"
        case .arabic: return "ar"
        case .thai: return "th"
        case .vietnamese: return "vi"
        }
    }

    // Languages available for source selection
    static var sourceLanguages: [Language] {
        return Language.allCases
    }
    
    // Languages available for target selection (Auto is not a valid target)
    static var targetLanguages: [Language] {
        return Language.allCases.filter { $0 != .auto }
    }
}
