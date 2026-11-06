import AppKit

/// A global shortcut written the way people type it: "ctrl+option+l", "cmd+shift+1", "⌃⌥L".
struct KeyCombo: Equatable, Hashable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    static func == (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .control, .option, .shift])
    }

    init(_ text: String) throws {
        let symbols: [Character: String] = ["⌘": "cmd", "⌃": "ctrl", "⌥": "option", "⇧": "shift"]
        var parts: [String] = []
        var rest = ""
        for character in text.trimmingCharacters(in: .whitespaces) {
            if let name = symbols[character] { parts.append(name) } else { rest.append(character) }
        }
        parts += rest.split(separator: "+", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty }
        if rest.hasSuffix("++") || rest == "+" { parts.append("+") }

        var modifiers: NSEvent.ModifierFlags = []
        var key: UInt16?
        for part in parts {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "ctrl", "control": modifiers.insert(.control)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            default:
                guard key == nil, let code = Self.keyCodes[part] else {
                    throw ModuleError.invalid("unrecognized shortcut “\(text)”")
                }
                key = code
            }
        }
        guard let key else { throw ModuleError.invalid("shortcut “\(text)” needs a key") }
        let isFunctionKey = Self.functionKeys.contains(key)
        guard isFunctionKey || !modifiers.intersection([.command, .control, .option]).isEmpty else {
            throw ModuleError.invalid("shortcut “\(text)” needs ⌘, ⌃ or ⌥")
        }
        self.init(keyCode: key, modifiers: modifiers)
    }

    /// "⌃⌥L", in the order macOS menus use.
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 53: "⎋"]
        let name = special[keyCode] ?? Self.keyCodes.first { $0.value == keyCode }?.key.uppercased() ?? "?"
        return text + name
    }

    /// The form written into module.json, e.g. "ctrl+option+l".
    var text: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        let names = Self.keyCodes.filter { $0.value == keyCode }.map(\.key)
        parts.append(names.min { ($0.count, $0) < ($1.count, $1) } ?? "space")
        return parts.joined(separator: "+")
    }

    private static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "space": 49, "return": 36, "enter": 36, "tab": 48, "esc": 53, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}
