import SwiftUI

struct ThemeColorSettingsView: View {
    @Bindable private var palette = ThemePalette.shared
    @AppStorage(AppDefaults.Keys.popupLiquidGlass) private var liquidGlassEnabled = AppDefaults.popupLiquidGlass
    @AppStorage(AppDefaults.Keys.popupTintHex) private var tintHex = AppDefaults.popupTintHex
    @AppStorage(AppDefaults.Keys.popupTintStrength) private var tintStrength = AppDefaults.popupTintStrength
    @State private var showAdvanced = false
    @State private var showPalettes = false

    var body: some View {
        HStack {
            Text("Color Palette".localized)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Button {
                showAdvanced = false
                showPalettes.toggle()
            } label: {
                HStack(spacing: 7) {
                    swatch(accent: AppColors.primary, tint: tintHex)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(minHeight: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Color Palette".localized)
            .accessibilityValue((selectedPreset?.name ?? "Custom Palette").localized)
            .popover(isPresented: $showPalettes, arrowEdge: .bottom) {
                Group {
                    if showAdvanced {
                        advancedControls
                            .padding(16)
                            .frame(width: 300)
                    } else {
                        paletteOptions
                    }
                }
                .presentationBackground {
                    ThemeBackground()
                }
            }

            Spacer()

            Button {
                WindowManager.shared.show(text: "")
            } label: {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Preview Popup".localized)
            .accessibilityLabel("Preview Popup".localized)
        }
        .font(.system(size: 13, design: .serif))
    }

    private var selectedPreset: ThemePreset? {
        ThemePreset.all.first {
            $0.matches(accent: palette.accentColorHex, tint: tintHex, strength: tintStrength)
        }
    }

    private var paletteOptions: some View {
        HStack(spacing: 7) {
            ForEach(ThemePreset.all) { preset in
                Button {
                    palette.accentColorHex = preset.accentHex
                    tintHex = preset.tintHex
                    tintStrength = preset.tintStrength
                    showPalettes = false
                } label: {
                    swatch(accent: Color(hex: preset.swatchAccentHex), tint: preset.tintHex)
                        .padding(4)
                        .overlay {
                            Capsule()
                                .strokeBorder(selectedPreset?.id == preset.id ? Color.primary.opacity(0.55) : .clear, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name.localized)
                .accessibilityAddTraits(selectedPreset?.id == preset.id ? [.isSelected] : [])
            }
            Divider().frame(height: 22).padding(.horizontal, 3)
            Button {
                showAdvanced = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .help("Advanced Customization".localized)
            .accessibilityLabel("Advanced Customization".localized)
        }
        .padding(10)
    }

    private func swatch(accent: Color, tint: String) -> some View {
        HStack(spacing: 0) {
            accent.frame(width: 16)
            Color(hex: tint)
        }
        .frame(width: 42, height: 12)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Customization".localized)
                .font(.system(size: 13, weight: .medium, design: .serif))

            ColorPicker("Theme Color".localized, selection: accentBinding, supportsOpacity: false)

            if #available(macOS 26.0, *) {
                VStack(alignment: .leading, spacing: 8) {
                    ColorPicker("Glass Tint".localized, selection: tintBinding, supportsOpacity: false)
                    HStack {
                        Text("Tint Strength".localized)
                        Slider(value: $tintStrength, in: 0...0.3, step: 0.01)
                            .accessibilityLabel("Tint Strength".localized)
                        Text("\(Int((tintStrength * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .disabled(!liquidGlassEnabled)
            }

            Button("Restore Default".localized) {
                palette.accentColorHex = AppDefaults.accentColorHex
                tintHex = AppDefaults.popupTintHex
                tintStrength = AppDefaults.popupTintStrength
            }
            .buttonStyle(.plain)
            .foregroundColor(AppColors.primary)
        }
        .font(.system(size: 12, design: .serif))
        .controlSize(.small)
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(hex: palette.accentColorHex.isEmpty ? "555386" : palette.accentColorHex) },
            set: { if let hex = $0.rgbHex { palette.accentColorHex = hex } }
        )
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: tintHex) },
            set: { color in
                if let hex = color.rgbHex {
                    tintHex = hex
                    if tintStrength == 0 { tintStrength = 0.1 }
                }
            }
        )
    }
}
