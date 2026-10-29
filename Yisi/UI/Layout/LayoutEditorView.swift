import SwiftUI

struct LayoutEditorView: View {
    @State private var frame: CGRect
    @State private var screenFrame: CGRect
    @State private var showVerticalGuide = false
    @State private var showHorizontalGuide = false
    @ObservedObject private var localizationManager = LocalizationManager.shared
    var onSave: (CGRect) -> Void
    var onCancel: () -> Void
    
    init(initialFrame: CGRect, screenFrame: CGRect, onSave: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        _frame = State(initialValue: initialFrame)
        _screenFrame = State(initialValue: screenFrame)
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        ZStack {
            // Fullscreen Frosted Background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            // Smart Guides
            GeometryReader { geo in
                if showVerticalGuide {
                    Path { path in
                        path.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                        path.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                    }
                    .stroke(Color.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4]))
                }
                
                if showHorizontalGuide {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                    }
                    .stroke(Color.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .ignoresSafeArea()
            
            // Instructions
            VStack(spacing: 20) {
                Text("Customize Popup Layout".localized)
                    .font(.system(size: 24, weight: .light, design: .serif))
                    .foregroundColor(.secondary)
                
                Text("Drag the window to position it. Drag the corner to resize.".localized)
                    .font(.system(size: 14, design: .serif))
                    .foregroundColor(.secondary.opacity(0.8))
                
                Spacer()
            }
            .padding(.top, 60)
            
            // Ghost Window
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // Window Body
                    ThemeBackground()
                        .frame(width: frame.width, height: frame.height)
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .overlay(
                            VStack(spacing: 16) {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("\(Int(frame.width)) × \(Int(frame.height))")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button(action: { onCancel() }) {
                                        Text("Cancel".localized)
                                            .font(.system(size: 12, design: .serif))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .keyboardShortcut(.escape, modifiers: [])
                                    
                                    Button(action: { onSave(frame) }) {
                                        Text("Save".localized)
                                            .font(.system(size: 12, design: .serif))
                                            .foregroundColor(Color(nsColor: .windowBackgroundColor))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.primary)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .keyboardShortcut(.return, modifiers: [])
                                }
                            }
                        )
                        .position(x: frame.midX, y: frame.midY)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    var newX = max(0, min(screenFrame.width - frame.width, value.location.x - frame.width / 2))
                                    var newY = max(0, min(screenFrame.height - frame.height, value.location.y - frame.height / 2))
                                    
                                    // Center Snapping
                                    let centerX = screenFrame.midX
                                    let centerY = screenFrame.midY
                                    let currentCenterX = newX + frame.width / 2
                                    let currentCenterY = newY + frame.height / 2
                                    let threshold: CGFloat = 20
                                    
                                    var snappedX = false
                                    var snappedY = false
                                    
                                    if abs(currentCenterX - centerX) < threshold {
                                        newX = centerX - frame.width / 2
                                        snappedX = true
                                    }
                                    
                                    if abs(currentCenterY - centerY) < threshold {
                                        newY = centerY - frame.height / 2
                                        snappedY = true
                                    }
                                    
                                    frame.origin = CGPoint(x: newX, y: newY)
                                    
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        showVerticalGuide = snappedX
                                        showHorizontalGuide = snappedY
                                    }
                                }
                                .onEnded { _ in
                                    withAnimation {
                                        showVerticalGuide = false
                                        showHorizontalGuide = false
                                    }
                                }
                        )
                    
                    // Resize Handle
                    Image(systemName: "arrow.down.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.primary.opacity(0.5))
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 18, height: 18))
                        .position(x: frame.maxX, y: frame.maxY)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newWidth = max(300, value.location.x - frame.minX)
                                    let newHeight = max(200, value.location.y - frame.minY)
                                    frame.size = CGSize(width: newWidth, height: newHeight)
                                }
                        )
                }
            }
        }
    }
}
