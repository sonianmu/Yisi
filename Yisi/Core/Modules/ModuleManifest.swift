import Foundation

/// The three things a module can be. Each has its own folder, file name and fields,
/// so a manifest says exactly what Yisi will do with it.
enum ModuleRole: String, CaseIterable, Codable {
    /// The model behind Yisi's built-in translation and learning: system + text (+ image) in, answer out.
    case provider
    /// Runs on the selected text or screenshot, from the popup or its own shortcut.
    case preset
    /// Translates text between languages when chosen under Translation → Other Sources.
    case translator

    /// `modules/providers`, `modules/presets`, `modules/translators`.
    var folder: String { rawValue + "s" }
    /// `provider.json`, `preset.json`, `translator.json`.
    var manifestFile: String { rawValue + ".json" }

    /// Fields this role adds to the common ones.
    fileprivate var ownKeys: Set<String> {
        switch self {
        case .provider: return ["vision"]
        case .preset: return ["accepts", "shortcut"]
        case .translator: return ["accepts", "languages"]
        }
    }

    /// Placeholders `http` bodies and headers may use.
    var httpVariables: Set<String> {
        switch self {
        case .provider: return ["system", "text", "image"]
        case .preset: return ["text", "image"]
        case .translator: return ["text", "source", "target", "image"]
        }
    }

    /// Placeholders prompt steps may use, besides `{{file:path}}`.
    var promptVariables: Set<String> {
        switch self {
        case .provider: return []
        case .preset: return ["text", "previous"]
        case .translator: return ["text", "source", "target", "previous"]
        }
    }
}

enum ModuleInput: String, Codable, CaseIterable {
    case text, image
}

/// One manifest file. Common fields: `schemaVersion`, `name`, `description` and exactly one way to run,
/// `prompt`, `http` or `command`. The id is the folder name.
struct ModuleManifest: Equatable {
    static let currentSchemaVersion = 1

    var role: ModuleRole
    var schemaVersion: Int = currentSchemaVersion
    var name: String
    var description: String?
    /// Presets and translators: what they read (default text). Images reach text-only modules as OCR text.
    var accepts: [ModuleInput]?
    /// Providers: whether the model can see images.
    var vision: Bool?
    /// Presets: a global shortcut such as "ctrl+option+p".
    var shortcut: String?
    /// Translators: Yisi's language codes mapped to the service's own, e.g. {"zh-Hans": "zh"}.
    var languages: [String: String]?
    var handler: ModuleHandler

    var inputs: Set<ModuleInput> {
        if role == .provider { return vision == true ? [.text, .image] : [.text] }
        return Set(accepts ?? [.text])
    }
    var acceptsImages: Bool { inputs.contains(.image) }

    func languageCode(_ code: String) -> String { languages?[code] ?? code }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ModuleError.invalid("schemaVersion must be \(Self.currentSchemaVersion)")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, name.count <= 80 else { throw ModuleError.invalid("name must be 1–80 characters") }
        guard (description?.count ?? 0) <= 400 else { throw ModuleError.invalid("description must be at most 400 characters") }
        guard accepts.map({ !$0.isEmpty }) ?? true else { throw ModuleError.invalid("accepts must not be empty") }
        if let shortcut { _ = try KeyCombo(shortcut) }
        try handler.validate(role: role)
    }

    /// Ids are folder names: lowercase letters, digits and dashes.
    static func isValidID(_ id: String) -> Bool {
        id.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil
    }
}

extension CodingUserInfoKey {
    /// The role a manifest is decoded as; set by whoever knows which file it came from.
    static let moduleRole = CodingUserInfoKey(rawValue: "yisi.moduleRole")!
}

extension ModuleManifest: Codable {
    private struct Key: CodingKey {
        let stringValue: String
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    private static let commonKeys: Set<String> = ["$schema", "schemaVersion", "name", "description"]

    init(from decoder: Decoder) throws {
        guard let role = decoder.userInfo[.moduleRole] as? ModuleRole else {
            throw ModuleError.invalid("unknown module role")
        }
        let container = try decoder.container(keyedBy: Key.self)
        let keys = Set(container.allKeys.map(\.stringValue))
        let handlers = keys.intersection(ModuleHandler.types)
        guard handlers.count == 1, let type = handlers.first else {
            throw ModuleError.invalid("\(role.manifestFile) needs exactly one of “prompt”, “http” or “command”")
        }
        if let unknown = keys.subtracting(Self.commonKeys).subtracting(role.ownKeys).subtracting(ModuleHandler.types).sorted().first {
            throw ModuleError.invalid("\(role.manifestFile) has no field “\(unknown)”")
        }
        self.role = role
        schemaVersion = try container.decode(Int.self, forKey: Key("schemaVersion"))
        name = try container.decode(String.self, forKey: Key("name"))
        description = try container.decodeIfPresent(String.self, forKey: Key("description"))
        accepts = try container.decodeIfPresent([ModuleInput].self, forKey: Key("accepts"))
        vision = try container.decodeIfPresent(Bool.self, forKey: Key("vision"))
        shortcut = try container.decodeIfPresent(String.self, forKey: Key("shortcut"))
        languages = try container.decodeIfPresent([String: String].self, forKey: Key("languages"))
        switch type {
        case "prompt": handler = .prompt(try container.decode(PromptHandler.self, forKey: Key(type)))
        case "http": handler = .http(try container.decode(HTTPHandler.self, forKey: Key(type)))
        default: handler = .command(try container.decode(CommandHandler.self, forKey: Key(type)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(schemaVersion, forKey: Key("schemaVersion"))
        try container.encode(name, forKey: Key("name"))
        try container.encodeIfPresent(description, forKey: Key("description"))
        try container.encodeIfPresent(accepts, forKey: Key("accepts"))
        try container.encodeIfPresent(vision, forKey: Key("vision"))
        try container.encodeIfPresent(shortcut, forKey: Key("shortcut"))
        try container.encodeIfPresent(languages, forKey: Key("languages"))
        switch handler {
        case .prompt(let handler): try container.encode(handler, forKey: Key("prompt"))
        case .http(let handler): try container.encode(handler, forKey: Key("http"))
        case .command(let handler): try container.encode(handler, forKey: Key("command"))
        }
    }
}

enum ModuleHandler: Equatable {
    case prompt(PromptHandler)
    case http(HTTPHandler)
    case command(CommandHandler)

    static let types: Set<String> = ["prompt", "http", "command"]

    var type: String {
        switch self {
        case .prompt: return "prompt"
        case .http: return "http"
        case .command: return "command"
        }
    }

    func validate(role: ModuleRole) throws {
        switch self {
        case .prompt(let handler):
            guard role != .provider else { throw ModuleError.invalid("a provider calls a model; use “http” or “command”") }
            try handler.validate(variables: role.promptVariables)
        case .http(let handler): try handler.validate(variables: role.httpVariables)
        case .command(let handler): try handler.validate()
        }
    }

    /// Secret names the user must enter in Yisi; values live in Keychain only.
    var secretNames: [String] {
        let templates: [String]
        switch self {
        case .prompt: templates = []
        case .http(let handler): templates = Array((handler.headers ?? [:]).values) + (handler.body ?? [:]).values.flatMap(\.strings)
        case .command(let handler): templates = Array((handler.env ?? [:]).values)
        }
        return ModuleTemplate.secrets(in: templates).sorted()
    }
}

// MARK: - prompt

/// Yisi runs the steps itself against an AI provider; no code, no server.
struct PromptHandler: Codable, Equatable {
    struct Step: Codable, Equatable {
        /// Inline text or `@file.md`. May use the role's placeholders and `{{file:path}}`.
        var system: String?
        /// Defaults to `{{text}}` for the first step and `{{previous}}` afterwards.
        var user: String?
    }

    /// "default" for the AI service in Settings, or the id of a provider module.
    var provider: String?
    var temperature: Double?
    var steps: [Step]

    var providerID: String { provider ?? "default" }

    func validate(variables: Set<String>) throws {
        guard (1...8).contains(steps.count) else { throw ModuleError.invalid("prompt needs 1–8 steps") }
        guard !providerID.isEmpty else { throw ModuleError.invalid("provider must not be empty") }
        if let temperature, !(0...2).contains(temperature) { throw ModuleError.invalid("temperature must be 0–2") }
        for step in steps {
            for template in [step.system, step.user].compactMap({ $0 }) {
                try ModuleTemplate.check(template, variables: variables, allowing: "file")
            }
        }
    }

    /// Every file this handler reads, as written (`@x.md` and `{{file:x}}`).
    var fileReferences: [String] {
        steps.flatMap { [$0.system, $0.user].compactMap { $0 } }.flatMap { template -> [String] in
            var paths = ModuleTemplate.tokens(in: template).filter { $0.name == "file" }.compactMap(\.argument)
            if template.hasPrefix("@") { paths.append(String(template.dropFirst())) }
            return paths
        }
    }
}

// MARK: - http

/// One HTTP request per run. Without `body` it posts the role's request JSON and reads
/// `{"text": "..."}` or a plain-text body; with `body` it fills that template instead.
struct HTTPHandler: Codable, Equatable {
    var url: String
    var method: String?
    var encoding: String?
    var headers: [String: String]?
    var body: [String: JSONValue]?
    var response: [String]?
    var timeout: Double?

    var httpMethod: String { (method ?? "POST").uppercased() }
    var bodyEncoding: String { encoding ?? (httpMethod == "GET" ? "query" : "json") }
    var timeoutInterval: TimeInterval { timeout ?? 30 }
    var destination: String { URL(string: url)?.host ?? url }

    private static let reservedHeaders: Set<String> = ["host", "content-length", "connection", "transfer-encoding", "cookie"]

    func validate(variables: Set<String>) throws {
        guard let parsed = URL(string: url), let host = parsed.host, !host.isEmpty,
              parsed.user == nil, parsed.password == nil, parsed.fragment == nil, !url.contains("{{"),
              parsed.scheme == "https" || (parsed.scheme == "http" && Self.isLoopback(host)) else {
            throw ModuleError.invalid("url must be HTTPS, or HTTP on localhost / 127.0.0.1 / ::1")
        }
        guard ["GET", "POST"].contains(httpMethod), ["json", "form", "query"].contains(bodyEncoding),
              (httpMethod == "GET") == (bodyEncoding == "query") else {
            throw ModuleError.invalid("use POST with json/form, or GET with query")
        }
        if body == nil && httpMethod == "GET" { throw ModuleError.invalid("GET requires a body template") }
        if let response, !(1...16).contains(response.count) { throw ModuleError.invalid("response must have 1–16 path components") }
        if let timeout, !(1...300).contains(timeout) { throw ModuleError.invalid("timeout must be 1–300 seconds") }
        for (key, value) in headers ?? [:] {
            guard key.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil,
                  !Self.reservedHeaders.contains(key.lowercased()), value.rangeOfCharacter(from: .newlines) == nil else {
                throw ModuleError.invalid("invalid or reserved header \(key)")
            }
            try ModuleTemplate.check(value, variables: variables, allowing: "secret")
        }
        for template in (body ?? [:]).values.flatMap(\.strings) {
            try ModuleTemplate.check(template, variables: variables, allowing: "secret")
        }
    }

    static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }
}

// MARK: - command

/// A local program Yisi starts per run: the request on stdin, text on stdout.
struct CommandHandler: Codable, Equatable {
    enum Stdin: String, Codable { case json, text }

    /// Absolute path, a path inside the module folder, or a name found on the login shell's PATH.
    var program: String
    var args: [String]?
    var stdin: Stdin?
    var timeout: Double?
    /// Values may use `{{secret:name}}`.
    var env: [String: String]?

    var arguments: [String] { args ?? [] }
    var stdinFormat: Stdin { stdin ?? .json }
    var timeoutInterval: TimeInterval { timeout ?? 120 }

    func validate() throws {
        guard !program.trimmingCharacters(in: .whitespaces).isEmpty, !program.contains("\n") else {
            throw ModuleError.invalid("program must not be empty")
        }
        if let timeout, !(1...600).contains(timeout) { throw ModuleError.invalid("timeout must be 1–600 seconds") }
        for (key, value) in env ?? [:] {
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                throw ModuleError.invalid("invalid environment variable \(key)")
            }
            for token in ModuleTemplate.tokens(in: value) where !(token.name == "secret" && token.argument != nil) {
                throw ModuleError.invalid("env values only support {{secret:name}}")
            }
        }
    }
}

// MARK: - Errors

enum ModuleError: LocalizedError, Equatable {
    case invalid(String)
    case notFound(String)
    case approvalRequired(String)
    case missingSecret(String)
    case needsImage
    case needsText
    case http(Int)
    case unreachable
    case timeout
    case emptyResult
    case responseTooLarge
    case invalidResponse
    case commandNotFound(String)
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return String(format: "Invalid module: %@".localized, reason)
        case .notFound(let id): return String(format: "Module “%@” was not found. Reload modules or check its folder.".localized, id)
        case .approvalRequired(let name): return String(format: "Review and allow “%@” in Settings → Modules first.".localized, name)
        case .missingSecret(let name): return String(format: "Enter the “%@” key for this module in Settings → Modules.".localized, name)
        case .needsImage: return "This module works on screenshots. Take a screenshot instead.".localized
        case .needsText: return "Select or type some text first.".localized
        case .http(let status): return String(format: "The module's service returned HTTP %@.".localized, String(status))
        case .unreachable: return "Could not reach the module's service. Check that it is running.".localized
        case .timeout: return "The module took too long and was stopped.".localized
        case .emptyResult: return "The module returned no text.".localized
        case .responseTooLarge: return "The module's response is too large.".localized
        case .invalidResponse: return "The module's response did not contain text where expected.".localized
        case .commandNotFound(let command): return String(format: "Command “%@” was not found. Use an absolute path.".localized, command)
        case .commandFailed(let status, let detail):
            let base = String(format: "The module's command exited with status %@.".localized, String(status))
            return detail.isEmpty ? base : base + "\n" + detail
        }
    }
}
