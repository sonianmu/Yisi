import SwiftUI
import AppKit

/// A preset's own shortcut, recorded in place on its row. Click, press the keys; Esc cancels, Delete clears.
/// A module's own shortcut shows until one is set here.
struct PresetShortcutField: View {
    let selection: String
    var fallback: String? = nil

    @ObservedObject private var shortcuts = GlobalShortcutManager.shared
    @State private var combo: KeyCombo?
    @State private var isRecording = false
    @State private var needsModifier = false
    @State private var isHovered = false
    @State private var monitor: Any?

    private var issue: String? { shortcuts.presetShortcutIssues[selection] }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { isRecording ? stopRecording() : startRecording() }) {
                Text(label)
                    .font(.system(size: 11, design: .serif))
                    .monospacedDigit()
                    .foregroundColor(color)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(issue ?? "")

            if combo != nil, isHovered, !isRecording {
                Button(action: { save(nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Shortcut".localized)
            }
        }
        .onHover { isHovered = $0 }
        .onAppear { combo = PresetShortcuts.combo(for: selection, fallback: fallback) }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording { return needsModifier ? "Requires Cmd/Ctrl/Opt".localized : "Press keys".localized }
        return combo?.displayString ?? "Shortcut".localized
    }

    private var color: Color {
        if isRecording { return needsModifier ? .orange : AppColors.primary }
        if combo == nil { return .secondary.opacity(isHovered ? 0.7 : 0.4) }
        return issue == nil ? .secondary : .orange
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        needsModifier = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func record(_ event: NSEvent) {
        switch event.keyCode {
        case 53: stopRecording()            // Esc
        case 51, 117: save(nil)             // Delete, Forward Delete
        default:
            let candidate = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags)
            // Validates the same way a module's file is read: a known key and ⌘, ⌃ or ⌥.
            guard KeyCombo.keyCodes.values.contains(candidate.keyCode), let valid = try? KeyCombo(candidate.text) else {
                needsModifier = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { needsModifier = false }
                return
            }
            save(valid)
        }
    }

    private func save(_ new: KeyCombo?) {
        stopRecording()
        PresetShortcuts.set(new, for: selection)
        combo = new
        GlobalShortcutManager.shared.refreshPresetShortcuts()
    }
}
