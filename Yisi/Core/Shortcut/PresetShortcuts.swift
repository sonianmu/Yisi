import Foundation

/// A global shortcut for each preset, keyed by its selection id: a hand-written preset's UUID or a module's `module:<id>`.
/// A module's own `shortcut` is the default. One set in Settings overrides it and lives in preferences, so the
/// agent's file is never rewritten; clearing it stores "" so the default stays off too.
enum PresetShortcuts {
    struct Binding: Equatable {
        let selection: String
        let name: String
        let combo: KeyCombo
    }

    static func combo(for selection: String, fallback: String? = nil, defaults: UserDefaults = .standard) -> KeyCombo? {
        let text = stored(in: defaults)[selection] ?? fallback
        guard let text, !text.isEmpty else { return nil }
        return try? KeyCombo(text)
    }

    static func set(_ combo: KeyCombo?, for selection: String, defaults: UserDefaults = .standard) {
        var all = stored(in: defaults)
        all[selection] = combo?.text ?? ""
        defaults.set(all, forKey: AppDefaults.Keys.presetShortcuts)
    }

    /// Forgets a preset that no longer exists.
    static func remove(_ selection: String, defaults: UserDefaults = .standard) {
        var all = stored(in: defaults)
        guard all.removeValue(forKey: selection) != nil else { return }
        defaults.set(all, forKey: AppDefaults.Keys.presetShortcuts)
    }

    /// Every preset that has a shortcut, hand-written ones first, in the order Settings lists them.
    static func bindings(presets: [PromptPreset], modules: [Module], defaults: UserDefaults = .standard) -> [Binding] {
        let written = presets.compactMap { preset in
            combo(for: preset.id.uuidString, defaults: defaults).map { Binding(selection: preset.id.uuidString, name: preset.name, combo: $0) }
        }
        let built = modules.filter { $0.role == .preset }.compactMap { module in
            combo(for: module.selection, fallback: module.manifest.shortcut, defaults: defaults)
                .map { Binding(selection: module.selection, name: module.name, combo: $0) }
        }
        return written + built
    }

    private static func stored(in defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: AppDefaults.Keys.presetShortcuts) as? [String: String] ?? [:]
    }
}
