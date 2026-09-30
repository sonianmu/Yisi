import SwiftUI
import ServiceManagement
import ScreenCaptureKit

@main
@MainActor
enum YisiApp {
    static func main() {
        // All windows are managed by AppDelegate. A SwiftUI Settings scene with
        // EmptyView can restore an extra, empty settings window at startup.
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        setupMainMenu()
        setupMenuBar()
        setupShortcutHandler()

        if !UserDefaults.standard.bool(forKey: AppDefaults.Keys.hasLaunchedBefore) {
            UserDefaults.standard.set(true, forKey: AppDefaults.Keys.hasLaunchedBefore)
            try? SMAppService.mainApp.register()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showWelcomeFromAbout),
            name: Notification.Name("ShowWelcome"),
            object: nil
        )

        let completed = UserDefaults.standard.bool(forKey: AppDefaults.Keys.welcomeCompleted)
        let savedStep = UserDefaults.standard.integer(forKey: AppDefaults.Keys.welcomeStep)
        let accessibilityGranted = AXIsProcessTrusted()
        let screenCaptureGranted = CGPreflightScreenCaptureAccess()
        NSLog("Yisi startup: path=%@ step=%ld accessibility=%d screenCapture=%d completed=%d",
              Bundle.main.bundlePath, savedStep, accessibilityGranted ? 1 : 0,
              screenCaptureGranted ? 1 : 0, completed ? 1 : 0)
        if !completed {
            if WelcomeProgress.shouldOpenHome(
                savedStep: savedStep,
                accessibilityGranted: accessibilityGranted,
                screenCaptureGranted: screenCaptureGranted
            ) {
                UserDefaults.standard.set(true, forKey: AppDefaults.Keys.welcomeCompleted)
                toggleSettings()
            } else {
                showWelcome()
            }
        }

        if UserDefaults.standard.bool(forKey: AppDefaults.Keys.autoCheckUpdates) {
            UpdateManager.shared.checkForUpdates(silent: true)
        }
    }

    private func setupMainMenu() {
        // NSHostingView still needs standard AppKit editing actions for shortcuts
        // such as Command-V in API key and service address fields.
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Yisi")
        let settings = NSMenuItem(title: "Settings".localized, action: #selector(toggleSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"),
            ("Cut", "cut:", "x"),
            ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"),
            ("Select All", "selectAll:", "a")
        ] {
            editMenu.addItem(withTitle: title.localized, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let image = createFlowIcon() {
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Yisi")
            }
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleMenuBarClick)
            button.target = self
        }
    }
    
    @objc private func handleMenuBarClick() {
        guard let event = NSApp.currentEvent else {
            toggleSettings()
            return
        }
        
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "History".localized, action: #selector(openHistory), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Settings".localized, action: #selector(openSettingsConfig), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit".localized, action: #selector(quitApp), keyEquivalent: ""))
            
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleSettings()
        }
    }
    
    @objc private func openHistory() {
        toggleSettings()
        NotificationCenter.default.post(name: Notification.Name("SwitchToHistory"), object: nil)
    }
    
    @objc private func openSettingsConfig() {
        toggleSettings()
        NotificationCenter.default.post(name: Notification.Name("SwitchToSettings"), object: nil)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func createFlowIcon() -> NSImage? {
        // Design: "Pure Lines"
        // 3 lines, left aligned
        // Widths: 14, 9, 5
        // Height: 2
        // Gap: 2.5
        // Color: Black/Dark (System Text Color)
        
        let size = NSSize(width: 22, height: 22) // Match CSS .menubar-icon-shape
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.setShouldAntialias(true)
        
        NSColor.controlTextColor.setFill() // Adapts to light/dark mode
        
        // Calculate vertical centering
        // Total height = 2*3 + 2.5*2 = 6 + 5 = 11
        // Top Y = (22 - 11) / 2 = 5.5
        
        let lineHeight: CGFloat = 2.0
        
        // Note: Cocoa coords (0,0) is bottom-left.
        // To match CSS "Top", we draw from top down or just calculate Y.
        // Let's draw from top (higher Y) to bottom (lower Y).
        // Center Y is 11.
        // Top line Y = 11 + 2.5 + 2 = 15.5? No.
        // Let's just use the calculated startY from bottom.
        // Bottom line Y = 5.5
        // Middle line Y = 5.5 + 2 + 2.5 = 10.0
        // Top line Y = 10.0 + 2 + 2.5 = 14.5
        
        // Wait, CSS order is usually top-down.
        // .bar:nth-child(1) width 92% (in harmonic flow)
        // Here: .ml-1 width 14px (Top)
        // .ml-2 width 9px (Middle)
        // .ml-3 width 5px (Bottom)
        
        let topY = 5.5 + 4.5 + 4.5 // 14.5
        let midY = 5.5 + 4.5       // 10.0
        let botY = 5.5             // 5.5
        
        // Draw Top Line (Width 14)
        let path1 = NSBezierPath(roundedRect: NSRect(x: 4, y: topY, width: 14, height: lineHeight), xRadius: 1, yRadius: 1)
        path1.fill()
        
        // Draw Middle Line (Width 9)
        let path2 = NSBezierPath(roundedRect: NSRect(x: 4, y: midY, width: 9, height: lineHeight), xRadius: 1, yRadius: 1)
        path2.fill()
        
        // Draw Bottom Line (Width 5)
        let path3 = NSBezierPath(roundedRect: NSRect(x: 4, y: botY, width: 5, height: lineHeight), xRadius: 1, yRadius: 1)
        path3.fill()
        
        image.unlockFocus()
        image.isTemplate = true // Allows system to recolor it (e.g. white in dark mode menu bar)
        
        return image
    }
    
    private func setupShortcutHandler() {
        // 翻译快捷键
        GlobalShortcutManager.shared.onShortcutTriggered = { [weak self] in
            self?.handleShortcut()
        }

        // 截图快捷键
        GlobalShortcutManager.shared.onScreenshotTriggered = { [weak self] in
            self?.handleScreenshotShortcut()
        }

        // 截图界面双击 -> 打开图片上传窗口
        ScreenCaptureManager.shared.onOpenUploadWindow = {
            DispatchQueue.main.async {
                WindowManager.shared.showImageUploadWindow()
            }
        }

        GlobalShortcutManager.shared.startMonitoring()
    }
    
    private func handleScreenshotShortcut() {
        ScreenCaptureManager.shared.startCapture { image in
            // 截图完成，显示翻译窗口（带图片上下文）
            DispatchQueue.main.async {
                WindowManager.shared.showWithImage(image: image)
            }
        }
    }
    
    @objc func toggleSettings() {
        if !UserDefaults.standard.bool(forKey: AppDefaults.Keys.welcomeCompleted) {
            if let window = welcomeWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                showWelcome()
            }
            return
        }
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: AppDefaults.settingsWindowWidth, height: AppDefaults.settingsWindowHeight),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Yisi Settings"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            
            let settingsView = SettingsView()
            
            window.contentView = NSHostingView(rootView: settingsView)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            
            settingsWindow = window
        }
        
        if let window = settingsWindow {
            if !window.isVisible {
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc private func showWelcomeFromAbout() {
        if welcomeWindow != nil { return }
        showWelcome(isReentry: true)
    }

    private func showWelcome(isReentry: Bool = false) {
        guard welcomeWindow == nil else { return }
        settingsWindow?.orderOut(nil)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.isRestorable = false

        let welcomeView = WelcomeView(forceStartFromHero: isReentry) { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                window.close()
                self?.welcomeWindow = nil
                self?.toggleSettings()
            }
        }
        window.contentView = NSHostingView(rootView: welcomeView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow = window
    }

    private func handleShortcut() {
        // Capture text synchronously on main thread BEFORE any async work.
        // AX API must read the focused element while the source app still has focus.
        let immediateResult = TextCaptureService.shared.captureViaAccessibilityPublic()
        
        Task {
            var text = immediateResult ?? ""
            var error: String? = nil
            
            // If synchronous AX capture failed, fall back to clipboard simulation
            if text.isEmpty {
                let result = await TextCaptureService.shared.captureSelectedText()
                switch result {
                case .success(let capturedText):
                    text = capturedText
                case .failure(let captureError):
                    switch captureError {
                    case .permissionDenied:
                        error = "Accessibility permission required to capture text."
                    case .noSelection:
                        break
                    }
                }
            }
            
            let finalText = text
            let finalError = error
            
            await MainActor.run {
                WindowManager.shared.show(text: finalText, error: finalError)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var isThinking = false
}

extension ColorScheme {
    init?(from string: String) {
        switch string {
        case "light": self = .light
        case "dark": self = .dark
        default: return nil
        }
    }
}
