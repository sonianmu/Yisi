import SwiftUI
import Observation

@Observable
final class ThemePalette {
    static let shared = ThemePalette()

    var accentColorHex: String {
        didSet { UserDefaults.standard.set(accentColorHex, forKey: AppDefaults.Keys.accentColorHex) }
    }

    private init() {
        accentColorHex = UserDefaults.standard.string(forKey: AppDefaults.Keys.accentColorHex) ?? AppDefaults.accentColorHex
    }
}

struct AppColors {
    // Core Palette (Dynamic)
    static var yisiPurple: Color { accentColor(light: "555386", dark: "9D9AC6", lightBlend: 0.12, darkBlend: 0.3) }
    
    static var yisiDeep: Color { accentColor(light: "413F6B", dark: "6A6896", lightBlend: 0.25, darkBlend: 0.1) }
    
    static var yisiLight: Color { accentColor(light: "7A78AD", dark: "B0AED6", lightBlend: -0.2, darkBlend: 0.45) }

    private static func accentColor(light: String, dark: String, lightBlend: Double, darkBlend: Double) -> Color {
        let customHex = ThemePalette.shared.accentColorHex
        return Color(dynamicProvider: { appearance in
            guard !customHex.isEmpty else {
                return Color(hex: appearance.isDarkMode ? dark : light)
            }
            let base = NSColor(Color(hex: customHex))
            let fraction = appearance.isDarkMode ? darkBlend : lightBlend
            let blend = appearance.isDarkMode || fraction < 0 ? NSColor.white : NSColor.black
            return Color(nsColor: base.blended(withFraction: abs(fraction), of: blend) ?? base)
        })
    }
    
    static var mist: Color {
        let customHex = ThemePalette.shared.accentColorHex
        return Color(dynamicProvider: { appearance in
            guard !customHex.isEmpty else {
                return Color(hex: appearance.isDarkMode ? "2A2836" : "EBEAF5")
            }
            let base = NSColor(Color(hex: customHex))
            return Color(nsColor: base.blended(withFraction: appearance.isDarkMode ? 0.82 : 0.92,
                                               of: appearance.isDarkMode ? .black : .white) ?? base)
        })
    }
    
    static let inkMain = Color(dynamicProvider: { appearance in
        appearance.isDarkMode ? Color(hex: "E6E5EB") : Color(hex: "1F1E2E") // Softened White for Dark Mode
    })
    
    // Glass Effects
    static let glassMenu = Color(dynamicProvider: { appearance in
        appearance.isDarkMode ? Color(hex: "1A1A24").opacity(0.65) : Color.white.opacity(0.65)
    })
    
    static let glassCard = Color(dynamicProvider: { appearance in
        appearance.isDarkMode ? Color(hex: "252433").opacity(0.85) : Color.white.opacity(0.85)
    })
    
    // Semantic Mapping
    static var primary: Color { yisiPurple }
    static var secondary: Color { yisiLight }
    static var background: Color { mist }
    static let text = inkMain
    static var selection: Color { mist }
}

extension NSAppearance {
    var isDarkMode: Bool {
        if self.name == .darkAqua || self.name == .vibrantDark || self.name == .accessibilityHighContrastDarkAqua || self.name == .accessibilityHighContrastVibrantDark {
            return true
        }
        return false
    }
}

extension Color {
    var rgbHex: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }

    init(dynamicProvider: @escaping (NSAppearance) -> Color) {
        self = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let swiftUIColor = dynamicProvider(appearance)
            return NSColor(swiftUIColor)
        }))
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
