#if DEBUG
import AppKit
import SwiftUI

/// `--render-snapshots=<folder>` draws key settings views offscreen into PNGs, so the UI can be
/// reviewed without a display (CI, a locked screen). Debug builds only.
@MainActor
enum SettingsSnapshots {
    static func render(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ModuleStore.shared
        var views: [(String, AnyView, CGSize)] = [
            ("modes", AnyView(page(ModesSettingsView())), CGSize(width: 560, height: 620)),
            ("translators", AnyView(page(TranslatorPicker())), CGSize(width: 560, height: 160)),
            ("data", AnyView(page(DataSettingsSection())), CGSize(width: 560, height: 180)),
            ("about", AnyView(page(AboutView())), CGSize(width: 414, height: 420)),
            ("translation", AnyView(page(TranslationSettingsView())), CGSize(width: 414, height: 420)),
            ("editor", AnyView(PresetEditor(preset: PromptPreset(id: UUID(), name: "", inputPerception: "", outputInstruction: ""),
                                            isNew: true, onSave: { _ in }, onCancel: {})), CGSize(width: 420, height: 520)),
        ]
        for role in ModuleRole.tabs {
            views.append(("modules-\(role.rawValue)", AnyView(page(ModulesSettingsView().onAppear {
                UserDefaults.standard.set(role.rawValue, forKey: ModulesPage.tabKey)
            })), CGSize(width: 414, height: 420)))
        }
        if let shout = store.module("shout") {
            store.allow(shout)
            views.append(("popup-module", AnyView(TranslationView(originalText: "Modules make Yisi yours.", mode: .module(shout))
                .frame(width: 600, height: 330)), CGSize(width: 600, height: 330)))
        }
        for module in store.modules {
            views.append(("detail-\(module.id)", AnyView(ModuleDetailView(module: module) {}), CGSize(width: 460, height: 640)))
        }
        draw(views, into: folder)

        // The same details once the user has pressed Allow.
        let pending = store.modules.filter { !store.isAllowed($0) }
        pending.forEach(store.allow)
        draw(pending.map { ("detail-\($0.id)-allowed", AnyView(ModuleDetailView(module: $0) {}), CGSize(width: 460, height: 640)) },
             into: folder)
    }

    private static func draw(_ views: [(String, AnyView, CGSize)], into folder: URL) {
        for scheme in [ColorScheme.light, .dark] {
            for (name, view, size) in views {
                let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97)))
                hosting.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                hosting.frame = CGRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(name.hasPrefix("popup") ? 2 : 0.2))
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
    }

    private static func page<Content: View>(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 24) { content }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
