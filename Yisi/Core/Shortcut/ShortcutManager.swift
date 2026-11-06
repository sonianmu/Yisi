import Cocoa
import Carbon

private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    guard hotKeyID.signature == GlobalShortcutManager.HotKeyConfig.signature else {
        return OSStatus(eventNotHandledErr)
    }

    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()

    switch hotKeyID.id {
    case GlobalShortcutManager.HotKeyConfig.translateID:
        DispatchQueue.main.async {
            manager.triggerCount += 1
            manager.onShortcutTriggered?()
        }
    case GlobalShortcutManager.HotKeyConfig.screenshotID:
        DispatchQueue.main.async {
            manager.onScreenshotTriggered?()
        }
    default:
        guard let module = manager.moduleID(for: hotKeyID.id) else { return OSStatus(eventNotHandledErr) }
        DispatchQueue.main.async {
            manager.onModuleTriggered?(module)
        }
    }
    return noErr
}

class GlobalShortcutManager: ObservableObject {
    static let shared = GlobalShortcutManager()

    enum HotKeyConfig {
        static let signature: FourCharCode = {
            let chars: [UInt8] = [0x59, 0x49, 0x53, 0x49] // "YISI"
            return FourCharCode(chars[0]) << 24
                 | FourCharCode(chars[1]) << 16
                 | FourCharCode(chars[2]) << 8
                 | FourCharCode(chars[3])
        }()
        static let translateID: UInt32 = 1
        static let screenshotID: UInt32 = 2
        /// Preset modules use ids from here on, in the order they are registered.
        static let firstModuleID: UInt32 = 100
    }

    private var eventHandler: EventHandlerRef?
    private var translateHotKeyRef: EventHotKeyRef?
    private var screenshotHotKeyRef: EventHotKeyRef?

    @Published var triggerCount = 0

    var onShortcutTriggered: (() -> Void)?
    var onScreenshotTriggered: (() -> Void)?
    /// Called with a preset module's id when its own shortcut is pressed.
    var onModuleTriggered: ((String) -> Void)?

    /// Why a module's shortcut is not active, keyed by module id.
    @Published private(set) var moduleShortcutIssues: [String: String] = [:]
    private var moduleHotKeys: [UInt32: (module: String, ref: EventHotKeyRef)] = [:]
    private var registeredModules: [Module] = []

    private var translateKeyCode: UInt16
    private var translateModifiers: NSEvent.ModifierFlags
    private var screenshotKeyCode: UInt16
    private var screenshotModifiers: NSEvent.ModifierFlags

    private init() {
        let t = Self.loadShortcut(
            keyKey: AppDefaults.Keys.globalShortcutKey,
            modKey: AppDefaults.Keys.globalShortcutModifiers,
            defaultKey: AppDefaults.globalShortcutKeyCode,
            defaultMods: AppDefaults.globalShortcutMods
        )
        translateKeyCode = t.keyCode
        translateModifiers = t.modifiers

        let s = Self.loadShortcut(
            keyKey: AppDefaults.Keys.screenshotShortcutKey,
            modKey: AppDefaults.Keys.screenshotShortcutModifiers,
            defaultKey: AppDefaults.screenshotShortcutKeyCode,
            defaultMods: AppDefaults.screenshotShortcutMods
        )
        screenshotKeyCode = s.keyCode
        screenshotModifiers = s.modifiers
    }

    private static func loadShortcut(
        keyKey: String, modKey: String,
        defaultKey: UInt16, defaultMods: NSEvent.ModifierFlags
    ) -> (keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let savedKey = UserDefaults.standard.integer(forKey: keyKey)
        let savedMods = UserDefaults.standard.integer(forKey: modKey)
        if savedKey != 0 {
            return (UInt16(savedKey), NSEvent.ModifierFlags(rawValue: UInt(savedMods)))
        }
        return (defaultKey, defaultMods)
    }

    // MARK: - Public API

    func updateShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        translateKeyCode = keyCode
        translateModifiers = modifiers
        UserDefaults.standard.set(Int(keyCode), forKey: AppDefaults.Keys.globalShortcutKey)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: AppDefaults.Keys.globalShortcutModifiers)
        registerTranslateHotKey()
        registerModuleShortcuts(registeredModules)
    }

    func updateScreenshotShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        screenshotKeyCode = keyCode
        screenshotModifiers = modifiers
        UserDefaults.standard.set(Int(keyCode), forKey: AppDefaults.Keys.screenshotShortcutKey)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: AppDefaults.Keys.screenshotShortcutModifiers)
        registerScreenshotHotKey()
        registerModuleShortcuts(registeredModules)
    }

    var currentScreenshotKeyCode: UInt16 { screenshotKeyCode }
    var currentScreenshotModifiers: NSEvent.ModifierFlags { screenshotModifiers }

    // MARK: - Module shortcuts

    /// Registers every preset module's shortcut. Conflicts are reported, never silently overridden.
    func registerModuleShortcuts(_ modules: [Module]) {
        for (_, entry) in moduleHotKeys { UnregisterEventHotKey(entry.ref) }
        moduleHotKeys = [:]
        registeredModules = modules.filter { $0.role == .preset && $0.manifest.shortcut != nil }
        var issues: [String: String] = [:]
        var taken: [KeyCombo: String] = [
            KeyCombo(keyCode: translateKeyCode, modifiers: translateModifiers): "Activate".localized,
            KeyCombo(keyCode: screenshotKeyCode, modifiers: screenshotModifiers): "Screenshot".localized,
        ]
        for (index, module) in registeredModules.enumerated() {
            guard let text = module.manifest.shortcut, let combo = try? KeyCombo(text) else { continue }
            if let owner = taken[combo] {
                issues[module.id] = String(format: "Same shortcut as “%@”".localized, owner)
                continue
            }
            let id = HotKeyConfig.firstModuleID + UInt32(index)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(combo.keyCode), carbonModifiers(from: combo.modifiers),
                                             EventHotKeyID(signature: HotKeyConfig.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                moduleHotKeys[id] = (module.id, ref)
                taken[combo] = module.name
            } else {
                issues[module.id] = "Shortcut is used by another app".localized
            }
        }
        moduleShortcutIssues = issues
    }

    fileprivate func moduleID(for hotKey: UInt32) -> String? { moduleHotKeys[hotKey]?.module }

    // MARK: - Carbon Hot Key Registration

    func startMonitoring() {
        stopMonitoring()
        installEventHandler()
        registerTranslateHotKey()
        registerScreenshotHotKey()
        registerModuleShortcuts(registeredModules)
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
    }

    private func registerTranslateHotKey() {
        unregisterTranslateHotKey()
        var hotKeyID = EventHotKeyID(
            signature: HotKeyConfig.signature,
            id: HotKeyConfig.translateID
        )
        let carbonKey = UInt32(translateKeyCode)
        let carbonMods = carbonModifiers(from: translateModifiers)

        RegisterEventHotKey(
            carbonKey,
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &translateHotKeyRef
        )
    }

    private func unregisterTranslateHotKey() {
        if let ref = translateHotKeyRef {
            UnregisterEventHotKey(ref)
            translateHotKeyRef = nil
        }
    }

    private func registerScreenshotHotKey() {
        unregisterScreenshotHotKey()
        var hotKeyID = EventHotKeyID(
            signature: HotKeyConfig.signature,
            id: HotKeyConfig.screenshotID
        )
        let carbonKey = UInt32(screenshotKeyCode)
        let carbonMods = carbonModifiers(from: screenshotModifiers)

        RegisterEventHotKey(
            carbonKey,
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &screenshotHotKeyRef
        )
    }

    private func unregisterScreenshotHotKey() {
        if let ref = screenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            screenshotHotKeyRef = nil
        }
    }

    private func stopMonitoring() {
        unregisterTranslateHotKey()
        unregisterScreenshotHotKey()
        for (_, entry) in moduleHotKeys { UnregisterEventHotKey(entry.ref) }
        moduleHotKeys = [:]
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        return mods
    }

    deinit {
        stopMonitoring()
    }
}
