import Foundation
import AppKit

/// `Yisi modules …` — lets an agent check and try modules from Terminal without the UI.
///
///     Yisi modules list
///     Yisi modules validate
///     Yisi modules run <id> [--text T] [--image file] [--source auto] [--target zh-Hans] [--system S]
@MainActor
enum ModuleCLI {
    static func main(_ arguments: [String]) -> Never {
        let store = ModuleStore()
        switch arguments.first {
        case "list":
            list(store)
            exit(0)
        case "validate":
            exit(validate(store))
        case "run":
            run(Array(arguments.dropFirst()), store: store)
        default:
            print("""
            Usage:
              Yisi modules list
              Yisi modules validate
              Yisi modules run <id> [--text TEXT] [--image FILE] [--source auto] [--target zh-Hans] [--system TEXT]

            --source and --target apply to translators, --system to providers.
            Modules live in \(store.home.modules.path)/{providers,presets,translators}
            Each folder has an AGENTS.md with the guide for that kind.
            """)
            exit(arguments.isEmpty || arguments.first == "help" || arguments.first == "--help" ? 0 : 2)
        }
    }

    private static func list(_ store: ModuleStore) {
        for module in store.modules {
            print("\(module.role.folder)/\(module.id)\t\(module.manifest.handler.type)\t\(module.name)")
        }
    }

    private static func validate(_ store: ModuleStore) -> Int32 {
        for module in store.modules {
            var notes: [String] = []
            if !store.isAllowed(module) { notes.append("needs approval in Settings → Modules") }
            let missing = module.manifest.handler.secretNames.filter { !store.hasSecret($0, for: module) }
            if !missing.isEmpty { notes.append("needs key: " + missing.joined(separator: ", ")) }
            print("✓ \(module.role.folder)/\(module.id)  \(module.manifest.handler.type)" + (notes.isEmpty ? "" : "  (\(notes.joined(separator: "; ")))"))
        }
        for issue in store.issues {
            print("✗ \(issue.folder)  \(issue.message)")
        }
        if store.modules.isEmpty && store.issues.isEmpty { print("No modules in \(store.home.modules.path)") }
        return store.issues.isEmpty ? 0 : 1
    }

    private static func run(_ arguments: [String], store: ModuleStore) -> Never {
        guard let id = arguments.first, let module = store.module(id) else {
            fail(arguments.first.map { id in
                store.issues.first { $0.folder.hasSuffix("/" + id) }?.message ?? "No module “\(id)”."
            } ?? "Name a module to run.")
        }
        var options: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else { fail("Unexpected argument \(key).") }
            options[String(key.dropFirst(2))] = arguments[index + 1]
            index += 2
        }
        var text = options["text"] ?? ""
        if text.isEmpty && options["image"] == nil && isatty(STDIN_FILENO) == 0 {
            text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        var image: Data?
        if let path = options["image"] {
            guard let picture = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath),
                  let png = AIService.shared.imageToData(picture) else { fail("Could not read image \(path).") }
            image = png
        }
        let request = ModuleRequest(text: text, image: image, source: options["source"] ?? "auto",
                                    target: options["target"] ?? "zh-Hans", system: options["system"] ?? "")

        // Unapproved modules may still run here, so agents can test them, but never with the user's keys.
        let allowed = store.isAllowed(module)
        let stream = store.runner.run(module, request) { name in
            guard allowed else { throw ModuleError.approvalRequired(module.name) }
            guard let value = ModuleStore.secret(name, module: module.id) else { throw ModuleError.missingSecret(name) }
            return value
        }
        Task { @MainActor in
            var produced = false
            var endsWithNewline = false
            do {
                for try await chunk in stream {
                    produced = produced || !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    endsWithNewline = chunk.hasSuffix("\n")
                    FileHandle.standardOutput.write(Data(chunk.utf8))
                }
                guard produced else { throw ModuleError.emptyResult }
                if !endsWithNewline { FileHandle.standardOutput.write(Data("\n".utf8)) }
                exit(0)
            } catch {
                fail(error.localizedDescription)
            }
        }
        RunLoop.main.run()
        exit(0)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
