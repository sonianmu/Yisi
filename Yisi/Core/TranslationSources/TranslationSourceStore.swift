import Foundation
import Combine

@MainActor
final class TranslationSourceStore: ObservableObject {
    static let shared = TranslationSourceStore()
    static let selectedKey = "external_translation_source"
    static let approvalsKey = "translation_source_approvals_v1"
    static let credentialService = "com.yisi.app"

    @Published private(set) var sources: [TranslationSource] = []
    @Published private(set) var loadErrors: [String] = []
    let directory: URL
    private let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.sonianmu.yisi/TranslationSources", isDirectory: true)
        self.defaults = defaults
        reload()
    }

    func reload() {
        var loaded: [TranslationSource] = []
        var failures: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                do {
                    let source = try Self.read(file)
                    guard file.lastPathComponent == source.id + ".json" else {
                        throw TranslationSourceError.invalid("filename must be <id>.json")
                    }
                    guard !loaded.contains(where: { $0.id == source.id }) else {
                        throw TranslationSourceError.invalid("duplicate source id")
                    }
                    loaded.append(source)
                } catch {
                    failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch { failures.append(error.localizedDescription) }
        sources = loaded
        loadErrors = failures
    }

    static func read(_ file: URL) throws -> TranslationSource {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 262_144 else {
            throw TranslationSourceError.invalid("configuration must be a regular JSON file under 256 KB")
        }
        let source = try JSONDecoder().decode(TranslationSource.self, from: Data(contentsOf: file))
        try source.validate()
        return source
    }

    func install(_ source: TranslationSource) throws {
        try source.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let destination = directory.appendingPathComponent(source.id + ".json")
        if FileManager.default.fileExists(atPath: destination.path),
           try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw TranslationSourceError.invalid("symbolic link destination")
        }
        if let existing = sources.first(where: { $0.id == source.id }), existing.fingerprint != source.fingerprint {
            revoke(existing)
        }
        try encoder.encode(source).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        reload()
    }

    func isApproved(_ source: TranslationSource) -> Bool {
        defaults.dictionary(forKey: Self.approvalsKey)?[source.id] as? String == source.fingerprint
    }

    func approve(_ source: TranslationSource) {
        var approvals = defaults.dictionary(forKey: Self.approvalsKey) ?? [:]
        approvals[source.id] = source.fingerprint
        defaults.set(approvals, forKey: Self.approvalsKey)
        objectWillChange.send()
    }

    func revoke(_ source: TranslationSource) {
        var approvals = defaults.dictionary(forKey: Self.approvalsKey) ?? [:]
        approvals.removeValue(forKey: source.id)
        defaults.set(approvals, forKey: Self.approvalsKey)
        objectWillChange.send()
    }

    func saveSecret(_ value: String, for source: TranslationSource) throws {
        guard !value.isEmpty else { throw TranslationSourceError.missingSecret }
        try KeychainHelper.shared.saveChecked(Data(value.utf8), service: Self.credentialService, account: "translation-source:" + source.id)
    }

    func hasSecret(for source: TranslationSource) -> Bool {
        KeychainHelper.shared.read(service: Self.credentialService, account: "translation-source:" + source.id)?.isEmpty == false
    }

    func deleteSecret(for source: TranslationSource) {
        KeychainHelper.shared.delete(service: Self.credentialService, account: "translation-source:" + source.id)
    }

    func translate(_ text: String, source: String, target: String) async throws -> String {
        reload()
        guard let selected = defaults.string(forKey: Self.selectedKey),
              let configuration = sources.first(where: { $0.id == selected }), isApproved(configuration) else {
            throw TranslationSourceError.approvalRequired
        }
        guard text.utf8.count <= 1_048_576 else { throw TranslationSourceError.invalid("input exceeds 1 MB") }
        let secret: String?
        if configuration.requiresSecret {
            secret = KeychainHelper.shared.read(service: Self.credentialService, account: "translation-source:" + configuration.id)
                .flatMap { String(data: $0, encoding: .utf8) }
        } else { secret = nil }
        return try await TranslationSourceClient.translate(text, source: source, target: target,
                                                           configuration: configuration, secret: secret)
    }
}
