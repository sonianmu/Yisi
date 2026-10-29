import Foundation
import CryptoKit

enum TranslationSourceError: LocalizedError {
    case invalid(String)
    case approvalRequired
    case missingSecret
    case http(Int)
    case invalidResponse
    case responseTooLarge
    case unavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return String(format: "Invalid translation source: %@".localized, reason)
        case .approvalRequired: return "Review and approve this source in Translation settings first.".localized
        case .missingSecret: return "Save this source's API key in Translation settings first.".localized
        case .http(let status): return String(format: "Translation source returned HTTP %@.".localized, String(status))
        case .invalidResponse: return "The source did not return translated text at the configured response path.".localized
        case .responseTooLarge: return "The translation source response is too large.".localized
        case .unavailable: return "Could not connect to this translation source. Check the service or start your local bridge.".localized
        case .timeout: return "The translation source timed out. Please try again.".localized
        }
    }
}

enum SourceJSON: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: SourceJSON]), array([SourceJSON]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: SourceJSON].self) { self = .object(value) }
        else { self = .array(try container.decode([SourceJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    func rendered(_ variables: [String: String]) throws -> SourceJSON {
        switch self {
        case .string(let template):
            var rendered = template
            let expression = try NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
            let matches = expression.matches(in: template, range: NSRange(template.startIndex..., in: template))
            for match in matches.reversed() {
                guard let keyRange = Range(match.range(at: 1), in: template),
                      let tokenRange = Range(match.range, in: rendered),
                      let replacement = variables[String(template[keyRange])] else {
                    throw TranslationSourceError.invalid("unknown template variable")
                }
                rendered.replaceSubrange(tokenRange, with: replacement)
            }
            return .string(rendered)
        case .object(let values): return .object(try values.mapValues { try $0.rendered(variables) })
        case .array(let values): return .array(try values.map { try $0.rendered(variables) })
        default: return self
        }
    }

    var scalar: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }
}

struct TranslationSource: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let id: String
    let name: String
    let endpoint: String
    let method: String
    let encoding: String
    let headers: [String: String]
    let parameters: [String: SourceJSON]
    let responsePath: [String]
    let languageMap: [String: String]
    let requiresSecret: Bool

    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: (try? encoder.encode(self)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }

    var destination: String { URL(string: endpoint)?.host ?? endpoint }

    func validate() throws {
        guard schemaVersion == 1 else { throw TranslationSourceError.invalid("unsupported schemaVersion") }
        guard id.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression) != nil,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else {
            throw TranslationSourceError.invalid("invalid id or name")
        }
        guard let url = URL(string: endpoint), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              !endpoint.contains("{{"),
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)) else {
            throw TranslationSourceError.invalid("use HTTPS, or HTTP on loopback only")
        }
        guard ["GET", "POST"].contains(method), ["json", "form", "query"].contains(encoding),
              (method == "GET") == (encoding == "query"), !responsePath.isEmpty, responsePath.count <= 16 else {
            throw TranslationSourceError.invalid("invalid method, encoding or responsePath")
        }
        let reserved = ["host", "content-length", "connection", "transfer-encoding", "cookie"]
        for (key, value) in headers {
            guard key.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil,
                  !reserved.contains(key.lowercased()), value.rangeOfCharacter(from: .newlines) == nil else {
                throw TranslationSourceError.invalid("invalid or reserved header")
            }
        }
        _ = try makeRequest(text: "test", source: "auto", target: "en", secret: requiresSecret ? "test" : nil)
    }

    func makeRequest(text: String, source: String, target: String, secret: String?) throws -> URLRequest {
        if requiresSecret && (secret?.isEmpty != false) { throw TranslationSourceError.missingSecret }
        let variables = ["text": text, "source": languageMap[source] ?? source,
                         "target": languageMap[target] ?? target, "secret": secret ?? ""]
        let rendered = try parameters.mapValues { try $0.rendered(variables) }
        guard var components = URLComponents(string: endpoint) else {
            throw TranslationSourceError.invalid("invalid endpoint")
        }
        var body: Data?
        if encoding == "json" {
            body = try JSONEncoder().encode(rendered)
        } else {
            let items = try rendered.keys.sorted().map { key -> URLQueryItem in
                guard let scalar = rendered[key]?.scalar else {
                    throw TranslationSourceError.invalid("form and query values must be scalars")
                }
                return URLQueryItem(name: key, value: scalar)
            }
            if encoding == "query" {
                components.queryItems = (components.queryItems ?? []) + items
                components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            } else {
                var form = URLComponents()
                form.queryItems = items
                body = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            }
        }
        guard let url = components.url else { throw TranslationSourceError.invalid("invalid endpoint") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            guard let renderedHeader = try SourceJSON.string(value).rendered(variables).scalar,
                  renderedHeader.rangeOfCharacter(from: .newlines) == nil else {
                throw TranslationSourceError.invalid("invalid rendered header")
            }
            request.setValue(renderedHeader, forHTTPHeaderField: key)
        }
        if encoding != "query" {
            request.setValue(encoding == "json" ? "application/json" : "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func translatedText(from data: Data) throws -> String {
        guard data.count <= 2_097_152 else { throw TranslationSourceError.responseTooLarge }
        guard let json = try? JSONDecoder().decode(SourceJSON.self, from: data) else {
            throw TranslationSourceError.invalidResponse
        }
        func extract(_ value: SourceJSON, path: ArraySlice<String>) -> [String] {
            guard let component = path.first else {
                if case .string(let text) = value { return [text] }
                return []
            }
            switch value {
            case .object(let object):
                return object[component].map { extract($0, path: path.dropFirst()) } ?? []
            case .array(let array):
                if component == "*" { return array.flatMap { extract($0, path: path.dropFirst()) } }
                if let index = Int(component), array.indices.contains(index) { return extract(array[index], path: path.dropFirst()) }
                return []
            default: return []
            }
        }
        let result = extract(json, path: responsePath[...]).joined(separator: "\n")
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationSourceError.invalidResponse
        }
        return result
    }
}

private final class SourceRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum TranslationSourceClient {
    static func translate(_ text: String, source: String, target: String, configuration: TranslationSource,
                          secret: String?, sessionConfiguration: URLSessionConfiguration = .ephemeral) async throws -> String {
        try configuration.validate()
        let request = try configuration.makeRequest(text: text, source: source, target: target, secret: secret)
        let settings = sessionConfiguration
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.urlCache = nil
        settings.timeoutIntervalForResource = 35
        let session = URLSession(configuration: settings, delegate: SourceRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw TranslationSourceError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw TranslationSourceError.http(response.statusCode) }
            guard response.expectedContentLength <= 2_097_152 else { throw TranslationSourceError.responseTooLarge }
            var data = Data()
            for try await byte in bytes {
                if data.count >= 2_097_152 { throw TranslationSourceError.responseTooLarge }
                data.append(byte)
            }
            return try configuration.translatedText(from: data)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? TranslationSourceError.timeout : TranslationSourceError.unavailable
        }
    }
}
