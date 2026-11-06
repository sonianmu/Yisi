import Foundation

/// An arbitrary JSON value, used for templated request bodies and for reading responses.
enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
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

    /// Renders every string leaf; numbers, booleans and keys are left alone.
    func mapStrings(_ transform: (String) throws -> String) rethrows -> JSONValue {
        switch self {
        case .string(let value): return .string(try transform(value))
        case .object(let values): return .object(try values.mapValues { try $0.mapStrings(transform) })
        case .array(let values): return .array(try values.map { try $0.mapStrings(transform) })
        default: return self
        }
    }

    /// Every string leaf, for static checks such as which secrets a body uses.
    var strings: [String] {
        switch self {
        case .string(let value): return [value]
        case .object(let values): return values.values.flatMap(\.strings)
        case .array(let values): return values.flatMap(\.strings)
        default: return []
        }
    }

    var scalar: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    /// Strings found at a path of keys, array indexes or `*`.
    func strings(at path: ArraySlice<String>) -> [String] {
        guard let component = path.first else {
            if case .string(let text) = self { return [text] }
            return []
        }
        switch self {
        case .object(let object):
            return object[component]?.strings(at: path.dropFirst()) ?? []
        case .array(let array):
            if component == "*" { return array.flatMap { $0.strings(at: path.dropFirst()) } }
            if let index = Int(component), array.indices.contains(index) { return array[index].strings(at: path.dropFirst()) }
            return []
        default:
            return []
        }
    }
}
