import Foundation

/// Encodes/decodes arbitrary JSON values (tool schemas and arguments).
struct AnyCodableJSON: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableJSON].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodableJSON].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        try encode(value, to: encoder)
    }

    private func encode(_ value: Any, to encoder: Encoder) throws {
        if let dict = value as? [String: Any] {
            var container = encoder.container(keyedBy: DynamicKey.self)
            for (key, nested) in dict {
                try encode(nested, to: container.superEncoder(forKey: DynamicKey(stringValue: key)!))
            }
        } else if let array = value as? [Any] {
            var container = encoder.unkeyedContainer()
            for nested in array {
                try encode(nested, to: container.superEncoder())
            }
        } else if let string = value as? String {
            var container = encoder.singleValueContainer()
            try container.encode(string)
        } else if let bool = value as? Bool {
            var container = encoder.singleValueContainer()
            try container.encode(bool)
        } else if let int = value as? Int {
            var container = encoder.singleValueContainer()
            try container.encode(int)
        } else if let double = value as? Double {
            var container = encoder.singleValueContainer()
            try container.encode(double)
        } else if let number = value as? NSNumber {
            var container = encoder.singleValueContainer()
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                try container.encode(number.boolValue)
            } else if number.doubleValue.rounded() == number.doubleValue,
                      abs(number.doubleValue) <= Double(Int.max) {
                try container.encode(number.intValue)
            } else {
                try container.encode(number.doubleValue)
            }
        } else if value is NSNull {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        } else {
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}
