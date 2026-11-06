import Foundation
import CryptoKit

/// A module folder that loaded and validated: `modules/<role>s/<id>/<role>.json`.
struct Module: Identifiable, Equatable {
    let manifest: ModuleManifest
    let folder: URL

    /// The folder name.
    var id: String { folder.lastPathComponent }
    var name: String { manifest.name }
    var role: ModuleRole { manifest.role }
    var manifestURL: URL { folder.appendingPathComponent(role.manifestFile) }

    /// How Settings stores a chosen module beside built-in choices: "module:<id>".
    static let selectionPrefix = "module:"
    var selection: String { Self.selectionPrefix + id }
    static func id(fromSelection value: String) -> String? {
        value.hasPrefix(selectionPrefix) ? String(value.dropFirst(selectionPrefix.count)) : nil
    }

    /// Resolves a path written in module.json: relative to the module folder, `~/…`, or absolute.
    func resolve(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded)
        return url.standardizedFileURL
    }

    func isInside(_ url: URL) -> Bool {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(base)
    }

    /// What allowing this module means, and the fingerprint the approval is bound to.
    /// Prompt modules that only read their own folder need no approval: their text goes to a provider
    /// that is already trusted. Anything that reaches a new destination or runs code does.
    var trust: ModuleTrust {
        switch manifest.handler {
        case .prompt(let handler):
            let outside = handler.fileReferences.map(resolve).filter { !isInside($0) }
            guard !outside.isEmpty else { return ModuleTrust(fingerprint: nil, actions: []) }
            let paths = Set(outside.map(\.path)).sorted()
            return ModuleTrust(fingerprint: Self.digest(["prompt", handler.providerID] + paths),
                               actions: paths.map { .reads(Self.abbreviate($0)) })
        case .http(let handler):
            return ModuleTrust(fingerprint: Self.digest(["http", Self.canonical(handler)]),
                               actions: [.sends(handler.url)])
        case .command(let handler):
            // Files the command runs are part of what is approved: editing them asks again.
            let files = ([handler.program] + handler.arguments).compactMap { argument -> String? in
                guard argument.contains("/") || FileManager.default.fileExists(atPath: folder.appendingPathComponent(argument).path) else { return nil }
                let url = resolve(argument)
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                return "\(url.path)|\(size)|\(modified)"
            }
            let line = ([handler.program] + handler.arguments).map(Self.quoted).joined(separator: " ")
            return ModuleTrust(fingerprint: Self.digest(["command", Self.canonical(handler)] + files),
                               actions: [.runs(line)])
        }
    }

    private static func canonical<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func digest(_ parts: [String]) -> String {
        SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func quoted(_ argument: String) -> String {
        argument.contains(" ") ? "\"\(argument)\"" : argument
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct ModuleTrust: Equatable {
    enum Action: Equatable {
        case sends(String)
        case runs(String)
        case reads(String)
    }

    /// nil when the module needs no approval.
    let fingerprint: String?
    let actions: [Action]

    var needsApproval: Bool { fingerprint != nil }
}

/// A folder under `modules/` that could not be loaded, shown to the user with its reason.
struct ModuleIssue: Identifiable, Equatable {
    let role: ModuleRole?
    /// Relative to `modules/`, e.g. "presets/polish".
    let folder: String
    let message: String
    var id: String { folder }
}
