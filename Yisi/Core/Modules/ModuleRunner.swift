import Foundation

/// What Yisi hands a module: text and/or an image in, text out.
struct ModuleRequest {
    var text: String
    var image: Data?
    /// Translators: "auto" or a language code such as "en" or "zh-Hans", already mapped through `languages`.
    var source: String = "auto"
    var target: String = "zh-Hans"
    /// Providers: the instructions Yisi's built-in pipeline wrote for the model.
    var system: String = ""

    /// Values for `{{…}}` placeholders and the request JSON, limited to what the role defines.
    func fields(for role: ModuleRole, image: String?) -> [String: String] {
        var fields = ["text": text]
        switch role {
        case .provider: fields["system"] = system
        case .preset: break
        case .translator:
            fields["source"] = source
            fields["target"] = target
        }
        if let image { fields["image"] = image }
        return fields
    }

    /// What `"stdin": "text"` receives: the text, after the instructions for providers.
    func plainText(for role: ModuleRole) -> String {
        role == .provider && !system.isEmpty ? system + "\n\n" + text : text
    }

    /// The JSON that `http` modules without a body template and `command` modules on JSON stdin receive.
    func contract(role: ModuleRole, image: String?) -> [String: Any] {
        var json: [String: Any] = fields(for: role, image: image)
        json["schemaVersion"] = 1
        json["role"] = role.rawValue
        return json
    }
}

/// Runs one module. Every handler produces a stream of text chunks; most produce exactly one.
struct ModuleRunner {
    typealias Complete = (_ provider: String, _ messages: [AIMessage], _ temperature: Double?) async throws -> String
    typealias Secret = (_ name: String) throws -> String

    var home: YisiHome = .shared
    var sessionConfiguration: URLSessionConfiguration = .ephemeral
    /// Sends prompt steps to an AI provider. Injected so the runner never depends on settings.
    var complete: Complete
    var recognizeText: (Data) async throws -> String = { try await LocalVisionService.shared.recognizeText(from: $0) }

    func run(_ module: Module, _ request: ModuleRequest, secret: @escaping Secret) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prepared = try await prepare(request, for: module.manifest)
                    switch module.manifest.handler {
                    case .prompt(let handler):
                        continuation.yield(try await runPrompt(handler, module: module, request: prepared))
                    case .http(let handler):
                        continuation.yield(try await runHTTP(handler, module: module, request: prepared, secret: secret))
                    case .command(let handler):
                        for try await chunk in CommandRunner(home: home).run(handler, module: module, request: prepared, secret: secret) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Collects the stream; for callers that need the whole answer.
    func text(_ module: Module, _ request: ModuleRequest, secret: @escaping Secret) async throws -> String {
        var result = ""
        for try await chunk in run(module, request, secret: secret) { result += chunk }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ModuleError.emptyResult }
        return trimmed
    }

    /// Images reach text-only modules as local OCR text; nothing is sent that the module did not ask for.
    /// Translators receive language codes in their own vocabulary.
    private func prepare(_ request: ModuleRequest, for manifest: ModuleManifest) async throws -> ModuleRequest {
        var request = request
        if manifest.role == .translator {
            request.source = manifest.languageCode(request.source)
            request.target = manifest.languageCode(request.target)
        }
        if let image = request.image, !manifest.acceptsImages {
            let recognized = try await recognizeText(image)
            request.text = request.text.isEmpty ? recognized : request.text + "\n\n" + recognized
            request.image = nil
        }
        if manifest.inputs == [.image], request.image == nil { throw ModuleError.needsImage }
        if manifest.role != .provider, request.image == nil,
           request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ModuleError.needsText
        }
        return request
    }

    // MARK: prompt

    private func runPrompt(_ handler: PromptHandler, module: Module, request: ModuleRequest) async throws -> String {
        var previous = ""
        for (index, step) in handler.steps.enumerated() {
            let variables = ["text": request.text, "source": request.source, "target": request.target, "previous": previous]
            var messages: [AIMessage] = []
            if let system = step.system {
                messages.append(AIMessage(role: .system, text: try renderPrompt(system, module: module, variables: variables)))
            }
            let user = try renderPrompt(step.user ?? (index == 0 ? "{{text}}" : "{{previous}}"), module: module, variables: variables)
            messages.append(AIMessage(role: .user, text: user, image: index == 0 ? request.image : nil))
            try Task.checkCancellation()
            previous = try await complete(handler.providerID, messages, handler.temperature)
        }
        return previous
    }

    /// `@file` loads a whole template; `{{file:path}}` inlines one. Included files may use variables
    /// but not include further files, and substituted text is never interpreted again.
    private func renderPrompt(_ template: String, module: Module, variables: [String: String], nested: Bool = false) throws -> String {
        if template.hasPrefix("@") {
            return try renderPrompt(try read(String(template.dropFirst()), in: module), module: module, variables: variables, nested: true)
        }
        return try ModuleTemplate.render(template) { token in
            if token.name == "file", let path = token.argument {
                guard !nested else { throw ModuleError.invalid("included files cannot include other files") }
                return try renderPrompt(try read(path, in: module), module: module, variables: variables, nested: true)
            }
            guard token.argument == nil, let value = variables[token.name] else {
                throw ModuleError.invalid("unknown placeholder {{\(token.name)}}")
            }
            return value
        }
    }

    private func read(_ path: String, in module: Module) throws -> String {
        let url = module.resolve(path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else {
            throw ModuleError.invalid("file not found: \(Module.abbreviate(url.path))")
        }
        guard (values.fileSize ?? .max) <= 262_144, let text = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw ModuleError.invalid("\(Module.abbreviate(url.path)) must be UTF-8 text under 256 KB")
        }
        return text
    }

    // MARK: http

    private func runHTTP(_ handler: HTTPHandler, module: Module, request: ModuleRequest, secret: @escaping Secret) async throws -> String {
        let urlRequest = try makeRequest(handler, role: module.role, request: request, secret: secret)
        let settings = sessionConfiguration
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.urlCache = nil
        settings.timeoutIntervalForResource = handler.timeoutInterval + 5
        let session = URLSession(configuration: settings, delegate: RefuseRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let limit = 2_097_152
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let response = response as? HTTPURLResponse else { throw ModuleError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw ModuleError.http(response.statusCode) }
            guard response.expectedContentLength <= limit else { throw ModuleError.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw ModuleError.responseTooLarge }
                data.append(byte)
            }
            return try Self.text(from: data, path: handler.response, mimeType: response.mimeType)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? ModuleError.timeout : ModuleError.unreachable
        }
    }

    func makeRequest(_ handler: HTTPHandler, role: ModuleRole, request: ModuleRequest, secret: @escaping Secret) throws -> URLRequest {
        let image = request.image?.base64EncodedString()
        var variables = request.fields(for: role, image: image)
        if role.httpVariables.contains("image"), variables["image"] == nil { variables["image"] = "" }
        let render: (String) throws -> String = { template in
            try ModuleTemplate.render(template) { token in
                if token.name == "secret", let name = token.argument { return try secret(name) }
                guard token.argument == nil, let value = variables[token.name] else {
                    throw ModuleError.invalid("unknown placeholder {{\(token.name)}}")
                }
                return value
            }
        }
        guard var components = URLComponents(string: handler.url) else { throw ModuleError.invalid("invalid endpoint") }
        var body: Data?
        if let template = handler.body {
            let rendered = try template.mapValues { try $0.mapStrings(render) }
            switch handler.bodyEncoding {
            case "json":
                body = try JSONEncoder().encode(rendered)
            default:
                let items = try rendered.keys.sorted().map { key -> URLQueryItem in
                    guard let value = rendered[key]?.scalar else { throw ModuleError.invalid("form and query values must be scalars") }
                    return URLQueryItem(name: key, value: value)
                }
                if handler.bodyEncoding == "query" {
                    components.queryItems = (components.queryItems ?? []) + items
                    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
                } else {
                    var form = URLComponents()
                    form.queryItems = items
                    body = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
                }
            }
        } else {
            body = try JSONSerialization.data(withJSONObject: request.contract(role: role, image: image), options: [.sortedKeys])
        }
        guard let url = components.url else { throw ModuleError.invalid("invalid endpoint") }
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: handler.timeoutInterval)
        urlRequest.httpMethod = handler.httpMethod
        urlRequest.httpBody = body
        for (key, value) in handler.headers ?? [:] {
            let rendered = try render(value)
            guard rendered.rangeOfCharacter(from: .newlines) == nil else { throw ModuleError.invalid("header \(key) contains a line break") }
            urlRequest.setValue(rendered, forHTTPHeaderField: key)
        }
        if handler.bodyEncoding != "query" {
            urlRequest.setValue(handler.bodyEncoding == "form" ? "application/x-www-form-urlencoded" : "application/json",
                                forHTTPHeaderField: "Content-Type")
        }
        return urlRequest
    }

    /// With a path: the strings found there, one per line. Without: `{"text": …}` or the body as plain text.
    static func text(from data: Data, path: [String]?, mimeType: String?) throws -> String {
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        let result: String
        if let path {
            guard let json else { throw ModuleError.invalidResponse }
            result = json.strings(at: path[...]).joined(separator: "\n")
        } else if let json, case .object = json {
            result = json.strings(at: ["text"]).joined(separator: "\n")
        } else if mimeType?.contains("json") == true {
            throw ModuleError.invalidResponse
        } else {
            result = String(decoding: data, as: UTF8.self)
        }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw path == nil ? ModuleError.emptyResult : ModuleError.invalidResponse
        }
        return result
    }
}

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
