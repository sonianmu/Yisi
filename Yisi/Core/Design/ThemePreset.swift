import Foundation

struct ThemeColors: Equatable {
    let accent: String
    let deep: String
    let secondary: String
    let mist: String
    let selection: String
    let onAccent: String
    let glassTint: String
}

struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let accentHex: String
    let light: ThemeColors
    let dark: ThemeColors
    let tintStrength: Double

    var swatchAccentHex: String { light.accent }
    var tintHex: String { light.glassTint }

    func colors(isDark: Bool) -> ThemeColors { isDark ? dark : light }

    static let original = ThemePreset(
        id: "original", name: "Original Purple", accentHex: "",
        light: ThemeColors(accent: "555386", deep: "413F6B", secondary: "7A78AD", mist: "EBEAF5",
                           selection: "EBEAF5", onAccent: "FFFFFF", glassTint: "EBEAF5"),
        dark: ThemeColors(accent: "9D9AC6", deep: "6A6896", secondary: "B0AED6", mist: "2A2836",
                          selection: "2A2836", onAccent: "1F1E2E", glassTint: "47425F"),
        tintStrength: 0.12
    )

    static let all: [ThemePreset] = [
        original,
        ThemePreset(id: "ink", name: "Ink Blue", accentHex: "3E5973",
                    light: ThemeColors(accent: "3E5973", deep: "2A415A", secondary: "5F758B", mist: "E9EFF4",
                                       selection: "DCE7EF", onAccent: "FFFFFF", glassTint: "D4E1EC"),
                    dark: ThemeColors(accent: "9BB8D2", deep: "617E99", secondary: "B3C7DA", mist: "242E38",
                                      selection: "304252", onAccent: "17232F", glassTint: "344C61"),
                    tintStrength: 0.12),
        ThemePreset(id: "jade", name: "Jade Green", accentHex: "3E6658",
                    light: ThemeColors(accent: "3E6658", deep: "2D4F43", secondary: "5C796B", mist: "E9F0EB",
                                       selection: "DCE8DF", onAccent: "FFFFFF", glassTint: "D5E3D9"),
                    dark: ThemeColors(accent: "9DBFAE", deep: "607F70", secondary: "BDD3C5", mist: "24312B",
                                      selection: "30473C", onAccent: "17281F", glassTint: "355244"),
                    tintStrength: 0.10),
        ThemePreset(id: "warm-red", name: "Warm Red", accentHex: "9C4F50",
                    light: ThemeColors(accent: "9C4F50", deep: "75383A", secondary: "936264", mist: "F6EDEC",
                                       selection: "F3E5E2", onAccent: "FFFFFF", glassTint: "EBD9D6"),
                    dark: ThemeColors(accent: "D5A3A0", deep: "A86F6C", secondary: "E1BEBA", mist: "342626",
                                      selection: "4E3333", onAccent: "301D1D", glassTint: "69433F"),
                    tintStrength: 0.08),
        ThemePreset(id: "soft-gold", name: "Soft Gold", accentHex: "876B28",
                    light: ThemeColors(accent: "876B28", deep: "685019", secondary: "827040", mist: "F6F1E5",
                                       selection: "F8F2E3", onAccent: "FFFFFF", glassTint: "EADFBE"),
                    dark: ThemeColors(accent: "D5BB7A", deep: "A38B52", secondary: "E3D1A2", mist: "332F23",
                                      selection: "484025", onAccent: "2D2617", glassTint: "655631"),
                    tintStrength: 0.06)
    ]

    static func forAccent(_ accent: String) -> ThemePreset? {
        let normalized = accent.uppercased()
        if normalized == original.light.accent { return original }
        return all.first { $0.accentHex == normalized }
    }

    #if DEBUG
    static let comparisonCandidates = all
    #endif

    func glassTint(storedHex: String, strength: Double, isDark: Bool) -> String {
        storedHex.uppercased() == tintHex && abs(strength - tintStrength) < 0.001
            ? colors(isDark: isDark).glassTint : storedHex
    }

    func matches(accent: String, tint: String, strength: Double) -> Bool {
        Self.forAccent(accent)?.id == id && tint.uppercased() == tintHex && abs(strength - tintStrength) < 0.001
    }
}
