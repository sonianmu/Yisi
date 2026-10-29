#if DEBUG
import SwiftUI

struct ThemePalettePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("五套配色 · 弹窗对比")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                Spacer()
                Text("相同布局与阅读遮罩 · 示例译文")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Color.clear.frame(width: 36)
                ForEach(["浅色", "深色", "密集文字背景"], id: \.self) { title in
                    Text(title).font(.system(size: 11, design: .serif))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(ThemePreset.comparisonCandidates.enumerated()), id: \.element.id) { index, preset in
                HStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Capsule().fill(Color(hex: preset.light.accent)).frame(width: 28, height: 7)
                    }
                    .frame(width: 36)
                    sample(preset, isDark: false)
                    sample(preset, isDark: true)
                    sample(preset, isDark: false, denseBackground: true)
                }
            }
        }
        .padding(20)
        .frame(width: 1040, height: 690)
        .background(Color(hex: "F0EFED"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .preferredColorScheme(.light)
    }

    private func sample(_ preset: ThemePreset, isDark: Bool, denseBackground: Bool = false) -> some View {
        let colors = preset.colors(isDark: isDark)
        return ZStack {
            Color(hex: isDark ? "222329" : "E8E9EC")
            if denseBackground {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<8) { index in
                        Text(index.isMultiple(of: 2) ? "项目进度、交付内容与阅读记录" : "合同条款 2026 / Design and details")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundStyle(Color(hex: "22232A"))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("EN").foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Text("简体中文").foregroundStyle(Color(hex: colors.secondary))
                    Spacer()
                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                }
                .font(.system(size: 10, design: .serif))
                Text("Stay focused on what matters.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("把注意力留给真正重要的事。")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color(hex: isDark ? "E6E5EB" : "1F1E2E"))
                    .fixedSize(horizontal: true, vertical: false)
                HStack {
                    Text("标准")
                        .font(.system(size: 10, design: .serif))
                        .foregroundStyle(Color(hex: colors.accent))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Color(hex: colors.selection), in: RoundedRectangle(cornerRadius: 4))
                    Spacer()
                    Text("Yisi")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(Color(hex: colors.onAccent))
                        .frame(width: 45, height: 24)
                        .background(Color(hex: colors.accent), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background { readingSurface(preset, isDark: isDark) }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: colors.deep).opacity(0.12), lineWidth: 0.5))
            .padding(denseBackground ? 6 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, isDark ? .dark : .light)
    }

    private func readingSurface(_ preset: ThemePreset, isDark: Bool) -> some View {
        let surface = Color(hex: isDark ? "1C1C1E" : "FAFAFA")
            .overlay(Color(hex: preset.colors(isDark: isDark).glassTint)
                .opacity(preset.tintStrength * (isDark ? 0.55 : 1)))
            .opacity(isDark ? 0.94 : 0.78)
        return Group {
            if #available(macOS 26.0, *) {
                surface.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                surface
            }
        }
    }
}
#endif
