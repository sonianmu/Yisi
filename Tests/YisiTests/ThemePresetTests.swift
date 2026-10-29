import XCTest
@testable import Yisi

final class ThemePresetTests: XCTestCase {
    func testOriginalPaletteRetainsExactLegacyColorsInBothAppearances() {
        let original = ThemePreset.original
        XCTAssertEqual(original.light.accent, "555386")
        XCTAssertEqual(original.dark.accent, "9D9AC6")
        XCTAssertEqual(original.light.deep, "413F6B")
        XCTAssertEqual(original.dark.deep, "6A6896")
        XCTAssertEqual(original.light.secondary, "7A78AD")
        XCTAssertEqual(original.dark.secondary, "B0AED6")
        XCTAssertEqual(original.light.mist, "EBEAF5")
        XCTAssertEqual(original.dark.mist, "2A2836")
        XCTAssertEqual(ThemePreset.forAccent("")?.id, original.id)
        XCTAssertEqual(ThemePreset.forAccent("555386")?.id, original.id)
        XCTAssertTrue(original.matches(accent: AppDefaults.accentColorHex, tint: AppDefaults.popupTintHex,
                                       strength: AppDefaults.popupTintStrength))
    }

    func testPresetsHaveDistinctIdentifiersAndCompleteAppearanceColors() {
        XCTAssertEqual(ThemePreset.all.first?.id, "original")
        XCTAssertEqual(Set(ThemePreset.all.map(\.id)).count, ThemePreset.all.count)
        for preset in ThemePreset.all {
            for colors in [preset.light, preset.dark] {
                for hex in [colors.accent, colors.deep, colors.secondary, colors.mist,
                            colors.selection, colors.onAccent, colors.glassTint] {
                    XCTAssertEqual(hex.count, 6)
                    XCTAssertNotNil(UInt32(hex, radix: 16))
                }
                XCTAssertNotEqual(colors.accent, colors.secondary)
                XCTAssertGreaterThanOrEqual(contrast(colors.accent, colors.onAccent), 4.5, preset.id)
                XCTAssertGreaterThanOrEqual(contrast(colors.accent, colors.selection), 4.5, preset.id)
                if preset.id != "original" {
                    XCTAssertGreaterThanOrEqual(contrast(colors.secondary, colors == preset.light ? "FAFAFA" : "1C1C1E"), 4.5, preset.id)
                }
            }
        }
    }

    func testOnlyUnmodifiedPresetTintAdaptsToDarkAppearance() {
        for preset in ThemePreset.all {
            XCTAssertEqual(preset.glassTint(storedHex: preset.tintHex, strength: preset.tintStrength, isDark: true),
                           preset.dark.glassTint)
            XCTAssertEqual(preset.glassTint(storedHex: preset.tintHex, strength: preset.tintStrength, isDark: false),
                           preset.light.glassTint)
            XCTAssertEqual(preset.glassTint(storedHex: "123456", strength: preset.tintStrength, isDark: true), "123456")
            XCTAssertEqual(preset.glassTint(storedHex: preset.tintHex, strength: 0.29, isDark: true), preset.tintHex)
        }
    }

    func testPreviousAndCustomAccentValuesAreNotSilentlyRemapped() {
        for accent in ["52606F", "68755E", "87745A", "80616B", "696485", "596F70", "123456"] {
            XCTAssertNil(ThemePreset.forAccent(accent))
        }
        XCTAssertEqual(ThemePreset.forAccent("3e5973")?.id, "ink")
    }

    private func contrast(_ first: String, _ second: String) -> Double {
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    func testFiveComparisonCandidatesHaveReadableControlsInBothAppearances() {
        XCTAssertEqual(ThemePreset.comparisonCandidates.map(\.id), ["original", "ink", "jade", "warm-red", "soft-gold"])
        for preset in ThemePreset.comparisonCandidates {
            for colors in [preset.light, preset.dark] {
                XCTAssertGreaterThanOrEqual(contrast(colors.accent, colors.onAccent), 4.5, preset.id)
                XCTAssertGreaterThanOrEqual(contrast(colors.accent, colors.selection), 4.5, preset.id)
            }
        }
    }

    private func luminance(_ hex: String) -> Double {
        let value = UInt32(hex, radix: 16)!
        let components = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { component in
            let channel = component / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}
