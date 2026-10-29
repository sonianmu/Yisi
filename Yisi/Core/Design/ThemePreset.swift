import Foundation

struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let accentHex: String
    let tintHex: String
    let tintStrength: Double

    var swatchAccentHex: String { accentHex.isEmpty ? "555386" : accentHex }

    static let all: [ThemePreset] = [
        ThemePreset(id: "ink", name: "Blue Gray", accentHex: "52606F", tintHex: "CAD1D8", tintStrength: 0.14),
        ThemePreset(id: "olive", name: "Gray Olive", accentHex: "68755E", tintHex: "CED1C3", tintStrength: 0.14),
        ThemePreset(id: "oat", name: "Oat", accentHex: "87745A", tintHex: "DDD0BA", tintStrength: 0.14),
        ThemePreset(id: "rose", name: "Dusty Rose", accentHex: "80616B", tintHex: "D9C8CC", tintStrength: 0.12),
        ThemePreset(id: "violet", name: "Smoky Violet", accentHex: "696485", tintHex: "D2CBDE", tintStrength: 0.12),
        ThemePreset(id: "teal", name: "Muted Teal", accentHex: "596F70", tintHex: "C4D2D0", tintStrength: 0.14)
    ]

    func matches(accent: String, tint: String, strength: Double) -> Bool {
        accent.uppercased() == accentHex && tint.uppercased() == tintHex && abs(strength - tintStrength) < 0.001
    }
}
