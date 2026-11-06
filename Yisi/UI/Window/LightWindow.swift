import Cocoa
import SwiftUI

class LightWindow: NSPanel {
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: backing,
            defer: flag
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        
        // Hide traffic light buttons for a cleaner look
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

class WindowManager: ObservableObject {
    static let shared = WindowManager()
    private var window: LightWindow?
    private var localMonitor: Any?
    
    private init() {}
    
    /// `mode` overrides the mode chosen in Settings for this popup only, as a preset's own shortcut does.
    func show(text: String, error: String? = nil, mode: TranslationView.Mode? = nil) {
        // Close existing window if any to ensure fresh window with correct size
        close()
        
        let appTheme = UserDefaults.standard.string(forKey: AppDefaults.Keys.appTheme) ?? AppDefaults.appTheme
        let contentView = TranslationView(originalText: text, errorMessage: error, mode: mode)
            .preferredColorScheme(ColorScheme(from: appTheme))
        
        let hostingController = NSHostingController(rootView: contentView)
        
        var contentRect: NSRect
        
        if let savedData = UserDefaults.standard.data(forKey: AppDefaults.Keys.popupFrameRect),
           let savedRect = try? JSONDecoder().decode(CGRect.self, from: savedData) {
            contentRect = savedRect
        } else {
            let windowSize = NSSize(width: AppDefaults.popupWindowWidth, height: AppDefaults.popupWindowHeight)
            let screenRect = NSScreen.main?.visibleFrame ?? NSRect.zero
            let centerPoint = NSPoint(x: screenRect.midX - windowSize.width / 2,
                                      y: screenRect.midY - windowSize.height / 2)
            contentRect = NSRect(origin: centerPoint, size: windowSize)
        }
        
        window = LightWindow(
            contentRect: contentRect,
            backing: .buffered,
            defer: false
        )
        window?.contentViewController = hostingController
        
        // Explicitly set the frame to ensure size is applied
        window?.setFrame(contentRect, display: true)
        
        print("Window created with frame: \(contentRect)")
        
        // Close on click outside if enabled
        let closeMode = UserDefaults.standard.string(forKey: AppDefaults.Keys.closeMode) ?? AppDefaults.closeMode
        print("DEBUG: Window created. Close mode: \(closeMode)")
        
        // IMPORTANT: Control whether the window hides (effectively closes) when the app loses focus (e.g. clicking desktop)
        window?.hidesOnDeactivate = (closeMode == "clickOutside")
        
        // Ensure any existing monitor is removed first (though close() should have handled it)
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        if closeMode == "clickOutside" {
            print("DEBUG: Adding click outside monitor")
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if let window = self?.window, event.window != window {
                    print("DEBUG: Click outside detected. Closing.")
                    self?.close()
                    return nil
                }
                return event
            }
        } else {
            print("DEBUG: Click outside monitor NOT added")
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// 显示带图片上下文的翻译窗口
    func showWithImage(image: NSImage, mode: TranslationView.Mode? = nil) {
        close()
        
        let appTheme = UserDefaults.standard.string(forKey: AppDefaults.Keys.appTheme) ?? AppDefaults.appTheme
        let contentView = TranslationView(originalText: "", errorMessage: nil, imageContext: image, mode: mode)
            .preferredColorScheme(ColorScheme(from: appTheme))
        
        let hostingController = NSHostingController(rootView: contentView)
        
        var contentRect: NSRect
        
        if let savedData = UserDefaults.standard.data(forKey: AppDefaults.Keys.popupFrameRect),
           let savedRect = try? JSONDecoder().decode(CGRect.self, from: savedData) {
            contentRect = savedRect
        } else {
            let windowSize = NSSize(width: AppDefaults.popupWindowWidth, height: AppDefaults.popupWindowHeight) // 稍大以容纳缩略图
            let screenRect = NSScreen.main?.visibleFrame ?? NSRect.zero
            let centerPoint = NSPoint(x: screenRect.midX - windowSize.width / 2,
                                      y: screenRect.midY - windowSize.height / 2)
            contentRect = NSRect(origin: centerPoint, size: windowSize)
        }
        
        window = LightWindow(
            contentRect: contentRect,
            backing: .buffered,
            defer: false
        )
        window?.contentViewController = hostingController
        window?.setFrame(contentRect, display: true)
        
        let closeMode = UserDefaults.standard.string(forKey: AppDefaults.Keys.closeMode) ?? AppDefaults.closeMode
        window?.hidesOnDeactivate = (closeMode == "clickOutside")
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        if closeMode == "clickOutside" {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if let window = self?.window, event.window != window {
                    self?.close()
                    return nil
                }
                return event
            }
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// 显示图片上传窗口（空状态，等待用户上传图片）
    func showImageUploadWindow() {
        close()
        
        let appTheme = UserDefaults.standard.string(forKey: AppDefaults.Keys.appTheme) ?? AppDefaults.appTheme
        let contentView = TranslationView(originalText: "", startInImageMode: true)
            .preferredColorScheme(ColorScheme(from: appTheme))
        
        let hostingController = NSHostingController(rootView: contentView)
        
        var contentRect: NSRect
        
        if let savedData = UserDefaults.standard.data(forKey: AppDefaults.Keys.popupFrameRect),
           let savedRect = try? JSONDecoder().decode(CGRect.self, from: savedData) {
            contentRect = savedRect
        } else {
            let windowSize = NSSize(width: AppDefaults.popupWindowWidth, height: AppDefaults.popupWindowHeight) // 与 showWithImage 一致
            let screenRect = NSScreen.main?.visibleFrame ?? NSRect.zero
            let centerPoint = NSPoint(x: screenRect.midX - windowSize.width / 2,
                                      y: screenRect.midY - windowSize.height / 2)
            contentRect = NSRect(origin: centerPoint, size: windowSize)
        }
        
        window = LightWindow(
            contentRect: contentRect,
            backing: .buffered,
            defer: false
        )
        window?.contentViewController = hostingController
        window?.setFrame(contentRect, display: true)
        
        let closeMode = UserDefaults.standard.string(forKey: AppDefaults.Keys.closeMode) ?? AppDefaults.closeMode
        window?.hidesOnDeactivate = (closeMode == "clickOutside")
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        
        if closeMode == "clickOutside" {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if let window = self?.window, event.window != window {
                    self?.close()
                    return nil
                }
                return event
            }
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        window?.close()
        window = nil
    }
    
    // MARK: - Close Detection Control
    
    /// 临时禁用关闭检测（用于打开文件选择器等场景）
    func suspendCloseDetection() {
        window?.hidesOnDeactivate = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    /// 恢复关闭检测
    func resumeCloseDetection() {
        let closeMode = UserDefaults.standard.string(forKey: AppDefaults.Keys.closeMode) ?? AppDefaults.closeMode
        
        window?.hidesOnDeactivate = (closeMode == "clickOutside")
        
        if closeMode == "clickOutside" && localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if let window = self?.window, event.window != window {
                    self?.close()
                    return nil
                }
                return event
            }
        }
    }
}
