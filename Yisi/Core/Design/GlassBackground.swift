import SwiftUI

struct GlassBackground: View {
    var isFloating = false
    var cornerRadius: CGFloat = 12
    @AppStorage(AppDefaults.Keys.popupLiquidGlass) private var liquidGlassEnabled = AppDefaults.popupLiquidGlass
    @AppStorage(AppDefaults.Keys.popupTintHex) private var tintHex = AppDefaults.popupTintHex
    @AppStorage(AppDefaults.Keys.popupTintStrength) private var tintStrength = AppDefaults.popupTintStrength
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency, colorSchemeContrast != .increased {
                readingSurface
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if liquidGlassEnabled && (reduceTransparency || colorSchemeContrast == .increased) {
                Color(hex: colorScheme == .dark ? "1C1C1E" : "FAFAFA")
            } else {
                ClassicThemeBackground()
            }
        }
        .allowsHitTesting(false)
    }

    private var readingSurface: some View {
        Color(hex: colorScheme == .dark ? "1C1C1E" : "FAFAFA")
            .overlay(Color(hex: resolvedTint).opacity(min(max(tintStrength, 0), 0.3) * (colorScheme == .dark ? 0.55 : 1)))
            .opacity(isFloating ? (colorScheme == .dark ? 0.30 : 0.16) : (colorScheme == .dark ? 0.94 : 0.78))
    }

    private var resolvedTint: String {
        ThemePreset.forAccent(ThemePalette.shared.accentColorHex)?
            .glassTint(storedHex: tintHex, strength: tintStrength, isDark: colorScheme == .dark) ?? tintHex
    }
}
