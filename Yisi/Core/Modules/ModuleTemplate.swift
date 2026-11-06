import Foundation

/// `{{name}}` and `{{kind:argument}}` placeholders.
///
/// Rendering is a single pass: substituted values are never interpreted again, so text
/// selected by the user can never inject a template of its own.
enum ModuleTemplate {
    struct Token: Equatable {
        let name: String
        let argument: String?
    }

    private static let expression = try! NSRegularExpression(pattern: #"\{\{\s*([A-Za-z]+)(?:\s*:\s*([^{}]*?))?\s*\}\}"#)

    static func tokens(in template: String) -> [Token] {
        expression.matches(in: template, range: NSRange(template.startIndex..., in: template)).compactMap { token(of: $0, in: template) }
    }

    static func render(_ template: String, resolve: (Token) throws -> String) throws -> String {
        var rendered = ""
        var cursor = template.startIndex
        for match in expression.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            guard let range = Range(match.range, in: template), let token = token(of: match, in: template) else { continue }
            rendered += template[cursor..<range.lowerBound]
            rendered += try resolve(token)
            cursor = range.upperBound
        }
        rendered += template[cursor...]
        return rendered
    }

    /// Throws on any placeholder other than the plain `variables` and `{{kind:argument}}` of the allowed kind.
    static func check(_ template: String, variables: Set<String>, allowing kind: String) throws {
        for token in tokens(in: template) {
            if token.name == kind, token.argument != nil { continue }
            guard variables.contains(token.name), token.argument == nil else {
                throw ModuleError.invalid("unknown placeholder {{\(token.name)\(token.argument.map { ":" + $0 } ?? "")}}")
            }
        }
    }

    /// Secret names referenced as `{{secret:name}}`.
    static func secrets(in templates: [String]) -> Set<String> {
        Set(templates.flatMap(tokens(in:)).filter { $0.name == "secret" }.compactMap(\.argument))
    }

    private static func token(of match: NSTextCheckingResult, in template: String) -> Token? {
        guard let name = Range(match.range(at: 1), in: template) else { return nil }
        let argument = Range(match.range(at: 2), in: template).map { String(template[$0]) }
        return Token(name: String(template[name]), argument: argument?.isEmpty == true ? nil : argument)
    }
}
