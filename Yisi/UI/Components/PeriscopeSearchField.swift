import SwiftUI

struct PeriscopeSearchField: View {
    @Binding var text: String
    @Binding var isVisible: Bool
    @Binding var isExpanded: Bool // New state for Capsule vs Detailed
    @FocusState private var isFocused: Bool
    
    // Physics
    private let animationCurve = Animation.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0)
    
    var body: some View {
        VStack {
            if isVisible {
                ZStack {
                    // Glass Background
                    // Animate between Label (100 or 140) and Bar (400)
                    ThemeBackground()
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                        // Dynamic Width based on state
                        .frame(width: isExpanded ? 400 : (text.isEmpty ? 100 : 160), height: 44)
                    
                    // Content
                    if isExpanded {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15, weight: .light))
                                .foregroundColor(.secondary)
                            
                            TextField("Search history...".localized, text: $text)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15, weight: .light, design: .serif))
                                .focused($isFocused)
                                .onSubmit { }
                            
                            if !text.isEmpty {
                                Button(action: { text = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2).delay(0.1)))
                    } else {
                        // Collapsed: Label or Active Filter
                        if text.isEmpty {
                            Text("Search".localized)
                                .font(.system(size: 13, weight: .medium, design: .serif))
                                .tracking(0.5)
                                .foregroundColor(.primary.opacity(0.7))
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            // Active Filter State ("Hidden Search Button")
                            // Minimalist: Just the text, centered.
                            Text(text)
                                .font(.system(size: 13, weight: .medium, design: .serif))
                                .foregroundColor(.primary.opacity(0.85)) // Slightly darker to show importance
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .frame(width: isExpanded ? 400 : (text.isEmpty ? 100 : 140), height: 44)
                .onTapGesture {
                    // Click to expand instantly
                    if !isExpanded {
                        withAnimation(animationCurve) {
                            isExpanded = true
                            isFocused = true
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                isFocused = true
            } else {
                isFocused = false
            }
        }
    }
}
