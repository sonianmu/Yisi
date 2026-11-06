import Foundation
import CryptoKit

/// Turns the translation sources of 1.3.13 into translator modules, once.
/// Sources the user had approved stay approved, and their Keychain key is carried over.
/// Hand-written presets are not modules and stay where they are.
@MainActor
enum ModuleMigration {
    static let doneKey = "modules_migration_v1"

    static func run(store: ModuleStore? = nil, defaults: UserDefaults = .standard,
                    legacySources: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("com.sonianmu.yisi/TranslationSources", isDirectory: true)) {
        guard !defaults.bool(forKey: doneKey) else { return }
        let store = store ?? .shared
        migrateSources(at: legacySources, store: store, defaults: defaults)
        defaults.set(true, forKey: doneKey)
        store.reload()
    }

    // MARK: Translation sources

    /// The v1 translation source format, decoded exactly as 1.3.13 stored it so approvals can be matched.
    private struct LegacySource: Codable {
        let schemaVersion: Int
        let id: String
        let name: String
        let endpoint: String
        let method: String
        let encoding: String
        let headers: [String: String]
        let parameters: [String: JSONValue]
        let responsePath: [String]
        let languageMap: [String: String]
        let requiresSecret: Bool

        var fingerprint: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func migrateSources(at directory: URL, store: ModuleStore, defaults: UserDefaults) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let approvals = defaults.dictionary(forKey: "translation_source_approvals_v1") as? [String: String] ?? [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let source = try? JSONDecoder().decode(LegacySource.self, from: data),
                  store.module(source.id) == nil else { continue }
            let secret: (String) -> String = { $0.replacingOccurrences(of: "{{secret}}", with: "{{secret:key}}") }
            let handler = HTTPHandler(url: source.endpoint, method: source.method, encoding: source.encoding,
                                      headers: source.headers.isEmpty ? nil : source.headers.mapValues(secret),
                                      body: source.parameters.mapValues { $0.mapStrings(secret) },
                                      response: source.responsePath, timeout: nil)
            let manifest = ModuleManifest(role: .translator, name: source.name,
                                          languages: source.languageMap.isEmpty ? nil : source.languageMap, handler: .http(handler))
            do {
                let module = try store.write(manifest, id: source.id)
                if approvals[source.id] == source.fingerprint { store.allow(module) }
                if let key = KeychainHelper.shared.read(service: ModuleStore.keychainService, account: "translation-source:" + source.id),
                   let value = String(data: key, encoding: .utf8), !value.isEmpty {
                    try? store.saveSecret(value, name: "key", for: module)
                }
            } catch {
                NSLog("Yisi could not migrate translation source %@: %@", source.id, error.localizedDescription)
            }
        }
    }
}
