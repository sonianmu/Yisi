import SwiftUI

struct ThemeBackground: View {
    var body: some View {
        GlassBackground()
    }
}

struct ClassicThemeBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            if colorScheme == .dark {
                // MARK: - Dark Mode: Muji Minimalism
                // Clean, matte, solid background. No purple, no shine.
                Color(hex: "1C1C1E")
                    .edgesIgnoringSafeArea(.all)
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            } else {
                // MARK: - Light Mode: Original Frost
                // Base: Frosted Glass
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                
                // Tint Overlay: Purely neutral/white
                
                // 1. General Sheen (Subtle Purple Tint)
                LinearGradient(
                    gradient: Gradient(colors: [
                        AppColors.yisiPurple.opacity(0.03),
                        Color.white.opacity(0.02)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // 2. Top Left Highlight
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0)
                    ]),
                    center: UnitPoint(x: 0.1, y: 0.2),
                    startRadius: 0,
                    endRadius: 300
                )
                
                // 3. Bottom Center Glow
                RadialGradient(
                    gradient: Gradient(colors: [
                        AppColors.yisiPurple.opacity(0.08),
                        AppColors.yisiPurple.opacity(0)
                    ]),
                    center: UnitPoint(x: 0.5, y: 1.0),
                    startRadius: 0,
                    endRadius: 400
                )
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
        }
    }
}
