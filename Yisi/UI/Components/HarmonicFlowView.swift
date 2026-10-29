import SwiftUI

struct HarmonicFlowView: View {
    let text: String
    
    // Colors from Design System
    private var barBaseColor: Color { AppColors.mist }
    private var barActiveColor: Color { AppColors.yisiLight }
    
    private let speed: Double = 1.8
    
    // Parse text into lines to mirror structure, simulating visual wrapping
    private var lines: [String] {
        if text.isEmpty {
            return ["", "", "", ""] // Fallback default
        }
        
        var visualLines: [String] = []
        let rawLines = text.components(separatedBy: .newlines)
        
        // Heuristic: Wrap every ~45 characters to simulate visual lines
        // Increased from 40 to better fill the space
        let maxCharsPerLine = 45
        
        for line in rawLines {
            if line.isEmpty {
                visualLines.append("")
                continue
            }
            
            var currentIndex = line.startIndex
            
            while currentIndex < line.endIndex {
                let remainingDistance = line.distance(from: currentIndex, to: line.endIndex)
                let chunkLength = min(maxCharsPerLine, remainingDistance)
                let nextIndex = line.index(currentIndex, offsetBy: chunkLength)
                
                // improved wrapping: try to break at space if possible
                var end = nextIndex
                if chunkLength == maxCharsPerLine && nextIndex < line.endIndex {
                    if let lastSpace = line[currentIndex..<nextIndex].lastIndex(of: " ") {
                        end = line.index(after: lastSpace)
                    }
                }
                
                let chunk = String(line[currentIndex..<end])
                visualLines.append(chunk)
                currentIndex = end
            }
        }
        
        return visualLines
    }
    
    // Calculate width ratio for a given line, normalized against the longest line
    private func widthRatio(for line: String, maxLen: Int) -> CGFloat {
        if text.isEmpty {
            // Default pattern
            return [0.92, 0.78, 0.85, 0.60][Int.random(in: 0...3)]
        }
        
        if line.isEmpty { return 0.3 } // Minimum width for empty lines
        
        // Normalize: The longest line in the current text should be ~100% width
        // But we clamp the denominator to at least 20 chars to avoid
        // very short words stretching to full screen width (unless user wants that?)
        // User said "沾满输出框" (fill the output box).
        // Let's use a dynamic denominator.
        
        let denominator = CGFloat(max(20, maxLen))
        let count = CGFloat(line.count)
        
        // Allow it to go up to 1.0 (full width)
        return min(1.0, max(0.2, count / denominator))
    }
    
    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height
            // Bar height = 12, Spacing = 10. Total per item = 22.
            // We also have vertical padding of 8 inside the view, plus the parent padding.
            // Let's be safe and calculate based on the internal spacing.
            let itemHeight: CGFloat = 22
            let maxLines = Int(max(1, (availableHeight - 16) / itemHeight))
            
            let currentLines = lines
            let maxLen = currentLines.map { $0.count }.max() ?? 45
            let visibleLines = currentLines.prefix(maxLines)
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(visibleLines.enumerated()), id: \.offset) { index, line in
                    HarmonicBar(
                        widthRatio: widthRatio(for: line, maxLen: maxLen),
                        delay: Double(index) * 0.1, // Faster cascade for potentially many lines
                        speed: speed,
                        baseColor: barBaseColor,
                        activeColor: barActiveColor
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }
}

struct HarmonicBar: View {
    let widthRatio: CGFloat
    let delay: Double
    let speed: Double
    let baseColor: Color
    let activeColor: Color
    
    @State private var isAnimating: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 6)
                .fill(isAnimating ? activeColor : baseColor)
                .frame(width: geometry.size.width * widthRatio, height: 12)
                .scaleEffect(x: isAnimating ? 1.0 : 0.9, y: 1.0, anchor: .leading)
                .opacity(isAnimating ? 1.0 : 0.5)
                .onAppear {
                    withAnimation(
                        Animation
                            .easeInOut(duration: speed / 2)
                            .repeatForever(autoreverses: true)
                            .delay(delay)
                    ) {
                        isAnimating = true
                    }
                }
        }
        .frame(height: 12)
    }
}
