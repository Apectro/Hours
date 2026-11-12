import Foundation

// The coding rules of the Connect protocol (v1), in one place.
//
// The protocol is additive: the server may add fields and enum values at any
// time, and a field with a default may be left out. So every wire type here
// decodes leniently — unknown keys are ignored (Codable's own behaviour), a
// missing or unreadable field with a default takes it (`Defaulted`), and an
// open set of words is a string-backed value rather than a Swift enum, so a
// word this version does not know is kept instead of failing the whole page.

/// What a field falls back to when it is missing, null or unreadable.
protocol ConnectDefault {
    associatedtype Value: Codable & Hashable & Sendable
    static var value: Value { get }
}

/// A field with a default, as the protocol's `.default(…)`: decoded when
/// there, the default otherwise. Always written.
@propertyWrapper
struct Defaulted<Fallback: ConnectDefault>: Codable, Hashable, Sendable {
    var wrappedValue: Fallback.Value

    init(wrappedValue: Fallback.Value = Fallback.value) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = (try? container.decode(Fallback.Value.self)) ?? Fallback.value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    /// A missing key is the default, not an error.
    func decode<Fallback>(_ type: Defaulted<Fallback>.Type, forKey key: Key) throws -> Defaulted<Fallback> {
        (try? decodeIfPresent(type, forKey: key)) ?? Defaulted()
    }
}

enum ConnectDefaults {
    enum False: ConnectDefault { static var value: Bool { false } }
    enum Zero: ConnectDefault { static var value: Int { 0 } }
    enum Three: ConnectDefault { static var value: Double { 3 } }
    enum Empty: ConnectDefault { static var value: String { "" } }
    enum NoStrings: ConnectDefault { static var value: [String] { [] } }
    enum NoInts: ConnectDefault { static var value: [Int] { [] } }
    enum NoCounts: ConnectDefault { static var value: [String: Double] { [:] } }
    enum Worker: ConnectDefault { static var value: ConnectV1.CrewRole { .worker } }
    enum Note: ConnectDefault { static var value: String { "note" } }
    enum Here: ConnectDefault { static var value: String { "here" } }
    enum Red: ConnectDefault { static var value: String { "red" } }
    enum IOS: ConnectDefault { static var value: String { "ios" } }
    enum NoOne: ConnectDefault { static var value: ConnectV1.DefectAssignee { ConnectV1.DefectAssignee(kind: "nobody", name: "") } }
    /// An empty list of anything.
    enum None<Element: Codable & Hashable & Sendable>: ConnectDefault {
        static var value: [Element] { [] }
    }
}

/// A word from an open set (a kind, a status, a reason): kept as written,
/// compared against the words this version knows.
protocol ConnectWord: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral where RawValue == String {
    init(rawValue: String)
}

// Coded as the bare string by the standard library's own RawRepresentable
// conformance.
extension ConnectWord {
    init(stringLiteral value: String) { self.init(rawValue: value) }
}

/// Any JSON, for the protocol's `unknown` fields (a server copy, error
/// details) and for comparing what was sent with what was meant.
enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value):
            if value.rounded() == value, abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case let .object(object) = self { return object[key] }
        return nil
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }

    /// Whether everything `self` says, `other` says too. A null or a missing
    /// key mean the same, as the protocol's nullable-optional fields do.
    func isContained(in other: JSONValue) -> Bool {
        switch (self, other) {
        case (.null, _):
            return true
        case let (.object(mine), .object(theirs)):
            return mine.allSatisfy { key, value in
                if case .null = value { return theirs[key] == nil || theirs[key] == .null }
                guard let there = theirs[key] else { return false }
                return value.isContained(in: there)
            }
        case let (.array(mine), .array(theirs)):
            return mine.count == theirs.count && zip(mine, theirs).allSatisfy { $0.isContained(in: $1) }
        default:
            return self == other
        }
    }
}

enum ConnectJSON {
    /// Sorted keys, so the same record always gives the same bytes (and the
    /// same content hash).
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}
