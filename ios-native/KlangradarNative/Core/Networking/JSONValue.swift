import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

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
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

typealias JSONObject = [String: JSONValue]

extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        guard case let .string(value) = self[key] else { return nil }
        return value
    }

    func number(_ key: String) -> Double? {
        guard case let .number(value) = self[key] else { return nil }
        return value
    }

    func integer(_ key: String) -> Int? {
        number(key).map(Int.init)
    }

    func bool(_ key: String) -> Bool? {
        guard case let .bool(value) = self[key] else { return nil }
        return value
    }

    func object(_ key: String) -> JSONObject? {
        guard case let .object(value) = self[key] else { return nil }
        return value
    }

    func array(_ key: String) -> [JSONValue] {
        guard case let .array(value) = self[key] else { return [] }
        return value
    }

    func objects(_ key: String) -> [JSONObject] {
        array(key).compactMap {
            guard case let .object(value) = $0 else { return nil }
            return value
        }
    }

    func strings(_ key: String) -> [String] {
        array(key).compactMap {
            guard case let .string(value) = $0 else { return nil }
            return value
        }
    }
}
