import Foundation

/// Minimal JSON value type used by the MCP server.
indirect enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case integer(Int)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var anyObject: Any {
        switch self {
        case .null:        return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .integer(let i): return i
        case .string(let s): return s
        case .array(let a): return a.map { $0.anyObject }
        case .object(let o):
            var d: [String: Any] = [:]
            for (k, v) in o { d[k] = v.anyObject }
            return d
        }
    }

    static func from(_ any: Any) -> JSONValue {
        if any is NSNull { return .null }
        if let b = any as? Bool { return .bool(b) }
        if let i = any as? Int { return .integer(i) }
        if let n = any as? Double { return .number(n) }
        if let n = any as? NSNumber {
            if CFNumberIsFloatType(n) { return .number(n.doubleValue) }
            return .integer(n.intValue)
        }
        if let s = any as? String { return .string(s) }
        if let a = any as? [Any] { return .array(a.map { JSONValue.from($0) }) }
        if let d = any as? [String: Any] {
            var o: [String: JSONValue] = [:]
            for (k, v) in d { o[k] = JSONValue.from(v) }
            return .object(o)
        }
        return .null
    }

    // Accessors
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var intValue: Int? {
        switch self {
        case .integer(let i): return i
        case .number(let n): return Int(n)
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .integer(let i): return Double(i)
        case .number(let n): return n
        default: return nil
        }
    }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}

enum JSON {
    static func decode(data: Data) throws -> JSONValue {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue.from(any)
    }
    static func encode(_ v: JSONValue) throws -> Data {
        try JSONSerialization.data(withJSONObject: v.anyObject, options: [.fragmentsAllowed, .sortedKeys])
    }
    static func encodeString(_ v: JSONValue) throws -> String {
        let d = try encode(v)
        return String(data: d, encoding: .utf8) ?? "{}"
    }
}
