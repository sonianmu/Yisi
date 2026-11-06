import Foundation
import Combine
import CoreServices

/// Loads `modules/providers`, `modules/presets` and `modules/translators`, watches them,
/// and keeps approvals and secrets.
///
/// Approvals live in `state/approvals.json` and are bound to each module's trust fingerprint,
/// so a module that starts sending text somewhere new or running different code asks again.
@MainActor
final class ModuleStore: ObservableObject {
    static let shared = ModuleStore(watch: true)
    nonisolated static let keychainService = "com.yisi.app"

    @Published private(set) var modules: [Module] = []
    @Published private(set) var issues: [ModuleIssue] = []
    @Published private(set) var approvals: [String: String] = [:]

    let home: YisiHome
    /// How removed module folders leave: the Trash, so a removal can always be undone.
    var discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    private var watcher: FolderWatcher?

    init(home: YisiHome = .shared, watch: Bool = false) {
        self.home = home
        try? home.prepare()
        reload()
        if watch {
            watcher = FolderWatcher(url: home.modules) { [weak self] in
                Task { @MainActor in self?.reload() }
            }
        }
    }

    // MARK: Loading

    func reload() {
        var loaded: [Module] = []
        var failures: [ModuleIssue] = []
        let roles = Dictionary(uniqueKeysWithValues: ModuleRole.allCases.map { ($0.folder, $0) })
        for entry in Self.folders(in: home.modules) where roles[entry.lastPathComponent] == nil {
            failures.append(ModuleIssue(role: nil, folder: entry.lastPathComponent,
                                        message: "move this folder into providers/, presets/ or translators/"))
        }
        for role in ModuleRole.allCases {
            let base = home.modules.appendingPathComponent(role.folder, isDirectory: true)
            for folder in Self.folders(in: base) {
                let path = role.folder + "/" + folder.lastPathComponent
                do {
                    guard ModuleManifest.isValidID(folder.lastPathComponent) else {
                        throw ModuleError.invalid("folder name must be lowercase letters, digits and dashes")
                    }
                    if let other = loaded.first(where: { $0.id == folder.lastPathComponent }) {
                        throw ModuleError.invalid("“\(other.role.folder)/\(other.id)” already uses this name")
                    }
                    loaded.append(Module(manifest: try Self.readManifest(in: folder, role: role), folder: folder))
                } catch ModuleError.invalid(let reason) {
                    failures.append(ModuleIssue(role: role, folder: path, message: reason))
                } catch {
                    failures.append(ModuleIssue(role: role, folder: path, message: error.localizedDescription))
                }
            }
        }
        let decodedApprovals = (try? Data(contentsOf: home.approvals))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        if loaded != modules { modules = loaded }
        if failures != issues { issues = failures }
        if decodedApprovals != approvals { approvals = decodedApprovals }
    }

    private static func folders(in directory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func readManifest(in folder: URL, role: ModuleRole) throws -> ModuleManifest {
        let file = folder.appendingPathComponent(role.manifestFile)
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else {
            throw ModuleError.invalid("\(role.manifestFile) is missing")
        }
        guard (values.fileSize ?? .max) <= 262_144 else { throw ModuleError.invalid("\(role.manifestFile) must be under 256 KB") }
        let manifest: ModuleManifest
        do {
            let decoder = JSONDecoder()
            decoder.userInfo[.moduleRole] = role
            manifest = try decoder.decode(ModuleManifest.self, from: Data(contentsOf: file))
        } catch let error as ModuleError {
            throw error
        } catch let DecodingError.keyNotFound(key, context) {
            throw ModuleError.invalid("missing “\(Self.path(context.codingPath + [key]))”")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw ModuleError.invalid("wrong type at “\(Self.path(context.codingPath))”")
        } catch let DecodingError.dataCorrupted(context) {
            throw ModuleError.invalid(context.codingPath.isEmpty ? "\(role.manifestFile) is not valid JSON" : "invalid value at “\(Self.path(context.codingPath))”")
        }
        try manifest.validate()
        return manifest
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }

    func module(_ id: String) -> Module? { modules.first { $0.id == id } }

    func modules(for role: ModuleRole) -> [Module] { modules.filter { $0.role == role } }

    // MARK: Trust

    func isAllowed(_ module: Module) -> Bool {
        guard let fingerprint = module.trust.fingerprint else { return true }
        return approvals[module.id] == fingerprint
    }

    func allow(_ module: Module) {
        guard let fingerprint = module.trust.fingerprint else { return }
        var next = approvals
        next[module.id] = fingerprint
        saveApprovals(next)
    }

    func revoke(_ module: Module) {
        var next = approvals
        next.removeValue(forKey: module.id)
        saveApprovals(next)
    }

    private func saveApprovals(_ next: [String: String]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(next) {
            try? data.write(to: home.approvals, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: home.approvals.path)
        }
        approvals = next
    }

    // MARK: Secrets

    nonisolated static func secretAccount(module: String, name: String) -> String { "module.\(module).\(name)" }

    nonisolated static func secret(_ name: String, module: String) -> String? {
        KeychainHelper.shared.read(service: keychainService, account: secretAccount(module: module, name: name))
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    func hasSecret(_ name: String, for module: Module) -> Bool { Self.secret(name, module: module.id) != nil }

    func saveSecret(_ value: String, name: String, for module: Module) throws {
        try KeychainHelper.shared.saveChecked(Data(value.utf8), service: Self.keychainService,
                                              account: Self.secretAccount(module: module.id, name: name))
        objectWillChange.send()
    }

    func deleteSecret(_ name: String, for module: Module) {
        KeychainHelper.shared.delete(service: Self.keychainService, account: Self.secretAccount(module: module.id, name: name))
        objectWillChange.send()
    }

    /// Why a module cannot run right now, if anything.
    func readiness(of module: Module) -> ModuleError? {
        if !isAllowed(module) { return .approvalRequired(module.name) }
        if let missing = module.manifest.handler.secretNames.first(where: { !hasSecret($0, for: module) }) {
            return .missingSecret(missing)
        }
        return nil
    }

    // MARK: Running

    var runner: ModuleRunner {
        ModuleRunner(home: home, complete: { provider, messages, temperature in
            try await AIService.shared.complete(messages, provider: provider, temperature: temperature)
        })
    }

    /// Streams a module's text. Refuses modules that are not allowed or miss a key.
    func run(_ module: Module, _ request: ModuleRequest) throws -> AsyncThrowingStream<String, Error> {
        if let problem = readiness(of: module) { throw problem }
        let id = module.id
        return runner.run(module, request) { name in
            guard let value = Self.secret(name, module: id) else { throw ModuleError.missingSecret(name) }
            return value
        }
    }

    /// The whole answer of a module by id; used where Yisi needs one result, such as provider modules.
    func text(_ id: String, _ request: ModuleRequest) async throws -> String {
        if module(id) == nil { reload() }
        guard let module = module(id) else { throw ModuleError.notFound(id) }
        var result = ""
        for try await chunk in try run(module, request) { result += chunk }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ModuleError.emptyResult }
        return trimmed
    }

    // MARK: Writing

    /// Writes a module folder the way an agent would. Used by migration and tests.
    @discardableResult
    func write(_ manifest: ModuleManifest, id: String, files: [String: String] = [:]) throws -> Module {
        guard ModuleManifest.isValidID(id) else { throw ModuleError.invalid("id must match [a-z0-9][a-z0-9-]{0,63}") }
        try manifest.validate()
        let folder = home.modules.appendingPathComponent(manifest.role.folder, isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) || module(id) != nil {
            throw ModuleError.invalid("a module named “\(id)” already exists")
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in files {
            guard !name.contains(".."), !name.hasPrefix("/") else { throw ModuleError.invalid("invalid file name \(name)") }
            try Data(text.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(manifest.role.manifestFile), options: .atomic)
        reload()
        return Module(manifest: manifest, folder: folder)
    }

    /// Moves the folder to the Trash, so a removal can always be undone in Finder.
    func remove(_ module: Module) throws {
        try discard(module.folder)
        revoke(module)
        for name in module.manifest.handler.secretNames { deleteSecret(name, for: module) }
        reload()
    }
}

/// Recursive FSEvents watcher with a short coalescing latency.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        stream = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
