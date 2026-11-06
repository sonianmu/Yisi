import Foundation

/// The single folder that holds everything a user owns.
///
///     ~/Library/Application Support/Yisi/
///       AGENTS.md   where an agent starts; each modules/<kind>/AGENTS.md has that kind's guide (written by Yisi)
///       schemas/    JSON Schema for each manifest (written by Yisi)
///       modules/    providers/, presets/, translators/: one folder per module (written by the user's agent)
///       data/       history, history images, learned rules
///       state/      approvals and scratch files (never exported)
///
/// App updates only refresh the `AGENTS.md` files and `schemas/`; `modules/` and `data/` are never touched.
struct YisiHome {
    static let shared = YisiHome()

    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else if let override = ProcessInfo.processInfo.environment["YISI_HOME"], !override.isEmpty {
            self.root = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            self.root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Yisi", isDirectory: true)
        }
    }

    var modules: URL { root.appendingPathComponent("modules", isDirectory: true) }
    var data: URL { root.appendingPathComponent("data", isDirectory: true) }
    var state: URL { root.appendingPathComponent("state", isDirectory: true) }
    var schemas: URL { root.appendingPathComponent("schemas", isDirectory: true) }
    var guide: URL { root.appendingPathComponent("AGENTS.md") }
    func guide(for role: ModuleRole) -> URL { folder(for: role).appendingPathComponent("AGENTS.md") }
    func folder(for role: ModuleRole) -> URL { modules.appendingPathComponent(role.folder, isDirectory: true) }
    var approvals: URL { state.appendingPathComponent("approvals.json") }
    var scratch: URL { state.appendingPathComponent("tmp", isDirectory: true) }
    var pendingImport: URL { state.appendingPathComponent("pending-import", isDirectory: true) }

    var historyDatabase: URL { data.appendingPathComponent("history.sqlite") }
    var learnedRulesDatabase: URL { data.appendingPathComponent("learned-rules.sqlite") }
    var settings: URL { data.appendingPathComponent("settings.json") }

    /// Creates the folders and refreshes the files Yisi owns. Safe to call on every launch.
    func prepare() throws {
        let manager = FileManager.default
        for folder in [root, modules, data, state, schemas, scratch] + ModuleRole.allCases.map(folder(for:)) {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try writeIfChanged(ModuleGuide.index, to: guide)
        for role in ModuleRole.allCases {
            try writeIfChanged(ModuleGuide.guide(for: role), to: guide(for: role))
        }
        // schemas/ belongs to Yisi: it always holds exactly the current set.
        for stale in (try? manager.contentsOfDirectory(atPath: schemas.path)) ?? [] where ModuleGuide.schemas[stale] == nil {
            try? manager.removeItem(at: schemas.appendingPathComponent(stale))
        }
        for (name, text) in ModuleGuide.schemas {
            try writeIfChanged(text, to: schemas.appendingPathComponent(name))
        }
    }

    private func writeIfChanged(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        if (try? Data(contentsOf: url)) == data { return }
        try data.write(to: url, options: .atomic)
    }
}
