import Cocoa

/// 屏幕截图选区 Overlay View
/// 使用 AppKit 实现丝滑的鼠标拖拽选区
class ScreenCaptureOverlayView: NSView {
    
    // MARK: - Callbacks
    
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onOpenUploadWindow: (() -> Void)?
    
    // MARK: - State
    
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isSelecting = false
    
    /// 手动双击检测 - 因为 Overlay Panel 的 clickCount 不可靠
    private var lastClickTime: TimeInterval = 0
    private var lastClickLocation: NSPoint = .zero
    private let doubleClickInterval: TimeInterval = 0.3
    private let doubleClickRadius: CGFloat = 5.0
    
    // MARK: - Colors
    
    /// 遮罩颜色（半透明黑色）
    private let maskColor = NSColor.black.withAlphaComponent(0.3)
    
    /// 选框边框颜色（App 主色调）
    private var borderColor: NSColor {
        // 使用 SwiftUI AppColors.primary 的等价色
        return NSColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0)
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // 启用 Layer 以提升渲染性能
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    // MARK: - Cursor
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        // ESC 键取消
        if event.keyCode == 53 {
            onCancel?()
        }
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        let currentTime = Date().timeIntervalSince1970
        let currentLocation = convert(event.locationInWindow, from: nil)
        
        // 检查是否为双击（时间间隔 + 位置接近）
        let timeDelta = currentTime - lastClickTime
        let distance = hypot(currentLocation.x - lastClickLocation.x, 
                            currentLocation.y - lastClickLocation.y)
        
        if timeDelta < doubleClickInterval && distance < doubleClickRadius {
            // 双击检测成功
            print("DEBUG: Manual double-click detected!")
            // 重置状态
            isSelecting = false
            startPoint = nil
            currentPoint = nil
            lastClickTime = 0
            onOpenUploadWindow?()
            return
        }
        
        // 记录本次点击
        lastClickTime = currentTime
        lastClickLocation = currentLocation
        
        // 单击：开始选区
        startPoint = currentLocation
        currentPoint = startPoint
        isSelecting = true
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isSelecting, let start = startPoint, let end = currentPoint else { return }
        isSelecting = false
        
        let selectionRect = normalizedRect(from: start, to: end)
        
        // 选区太小则重置状态（不取消截图，允许用户继续操作/双击）
        if selectionRect.width < 10 || selectionRect.height < 10 {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        
        onSelectionComplete?(selectionRect)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // 右键：取消截图
        onCancel?()
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 1. 绘制全屏遮罩
        context.setFillColor(maskColor.cgColor)
        context.fill(bounds)
        
        // 2. 如果正在选择，绘制选框
        if isSelecting, let start = startPoint, let end = currentPoint {
            let selectionRect = normalizedRect(from: start, to: end)
            
            // 清除选区内的遮罩（挖洞效果）
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            
            // 恢复正常混合模式
            context.setBlendMode(.normal)
            
            // 绘制选框边框
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(1.0)
            context.stroke(selectionRect.insetBy(dx: 0.5, dy: 0.5))
            
            // 绘制尺寸标签
            drawSizeLabel(for: selectionRect, in: context)
        }
        
        // 3. 绘制操作指引 HUD
        drawHUD()
    }
    
    /// 绘制操作指引 HUD
    private func drawHUD() {
        let hudText = "Drag to select · Double-click to upload · Right-click to cancel".localized
        let attributes: [NSAttributedString.Key: Any] = [
            .font: YisiType.nsFont(size: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = (hudText as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 16
        let verticalPadding: CGFloat = 10
        let hudHeight: CGFloat = textSize.height + verticalPadding * 2
        let hudWidth = textSize.width + horizontalPadding * 2
        
        // 位置：屏幕底部向上约 100pt，水平居中
        let hudOrigin = CGPoint(
            x: bounds.midX - hudWidth / 2,
            y: 100
        )
        
        // 绘制胶囊背景
        let hudRect = CGRect(origin: hudOrigin, size: CGSize(width: hudWidth, height: hudHeight))
        let bgPath = NSBezierPath(roundedRect: hudRect, xRadius: hudHeight / 2, yRadius: hudHeight / 2)
        NSColor.black.withAlphaComponent(0.6).setFill()
        bgPath.fill()
        
        // 绘制文字
        let textOrigin = CGPoint(
            x: hudOrigin.x + horizontalPadding,
            y: hudOrigin.y + verticalPadding
        )
        (hudText as NSString).draw(at: textOrigin, withAttributes: attributes)
    }
    
    /// 绘制尺寸标签
    private func drawSizeLabel(for rect: CGRect, in context: CGContext) {
        let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: YisiType.nsFont(size: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = (sizeText as NSString).size(withAttributes: attributes)
        let labelPadding: CGFloat = 6
        let labelHeight: CGFloat = 20
        let labelWidth = textSize.width + labelPadding * 2
        
        // 标签位置：选框下方居中
        var labelOrigin = CGPoint(
            x: rect.midX - labelWidth / 2,
            y: rect.minY - labelHeight - 8
        )
        
        // 确保标签在屏幕内
        if labelOrigin.y < 0 {
            labelOrigin.y = rect.maxY + 8
        }
        
        // 绘制背景
        let labelRect = CGRect(origin: labelOrigin, size: CGSize(width: labelWidth, height: labelHeight))
        let bgPath = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        bgPath.fill()
        
        // 绘制文字
        let textOrigin = CGPoint(
            x: labelOrigin.x + labelPadding,
            y: labelOrigin.y + (labelHeight - textSize.height) / 2
        )
        (sizeText as NSString).draw(at: textOrigin, withAttributes: attributes)
    }
    
    // MARK: - Helpers
    
    /// 规范化矩形（确保宽高为正）
    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> CGRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
