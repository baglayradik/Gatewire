public import Alamofire
public import Foundation

/// Декодирует значение, вложенное в ответ по пути из ключей, без отдельного типа-обёртки.
///
/// ```swift
/// // { "data": { "items": [ ... ] } }
/// let posts = try await client.request(
///     UserRouter.posts(userID: 42, page: 1),
///     decoder: .nested([PostDTO].self, at: "data.items")
/// )
/// ```
///
/// Ключи пути проходят через `keyDecodingStrategy` декодера: при `.convertFromSnakeCase`
/// ключ `user_data` указывается как `userData`.
public struct NestedResponseDecoder<Value: Decodable & Sendable>: ResponseDecoder {
    /// Ключи пути от корня ответа до значения.
    public let keyPath: [String]

    /// Декодер данных. Если `nil`, используется ``ResponseDecodingContext/dataDecoder``.
    public let decoder: (any DataDecoder)?

    /// Создаёт декодер.
    ///
    /// - Parameters:
    ///   - type: Тип значения.
    ///   - keyPath: Путь из ключей через точку, например `"data"` или `"data.items"`.
    ///   - decoder: Декодер данных. По умолчанию `nil` — декодер эндпоинта или клиента.
    public init(_ type: Value.Type = Value.self, at keyPath: String, decoder: (any DataDecoder)? = nil) {
        self.keyPath = keyPath.split(separator: ".").map(String.init)
        self.decoder = decoder
    }

    public func decode(_ data: Data, context: ResponseDecodingContext) throws -> Value {
        // Путь передаётся в init(from:) через task-local значение: так работает любой DataDecoder,
        // а общий экземпляр декодера не изменяется.
        try NestedKeyPath.$current.withValue(keyPath) {
            try (decoder ?? context.dataDecoder).decode(NestedValue<Value>.self, from: data).value
        }
    }
}

extension ResponseDecoder {
    /// Декодер значения, вложенного в ответ по пути из ключей.
    ///
    /// - Parameters:
    ///   - type: Тип значения.
    ///   - keyPath: Путь из ключей через точку, например `"data"` или `"data.items"`.
    ///   - decoder: Декодер данных. По умолчанию `nil` — декодер эндпоинта или клиента.
    public static func nested<Value>(
        _ type: Value.Type,
        at keyPath: String,
        decoder: (any DataDecoder)? = nil
    ) -> Self where Self == NestedResponseDecoder<Value> {
        NestedResponseDecoder(type, at: keyPath, decoder: decoder)
    }
}

private enum NestedKeyPath {
    @TaskLocal static var current: [String] = []
}

private struct NestedValue<Value: Decodable>: Decodable {
    let value: Value

    init(from decoder: any Decoder) throws {
        let keys = NestedKeyPath.current
        guard let lastKey = keys.last else {
            value = try Value(from: decoder)
            return
        }

        var container = try decoder.container(keyedBy: PathKey.self)
        for key in keys.dropLast() {
            container = try container.nestedContainer(keyedBy: PathKey.self, forKey: PathKey(key))
        }
        value = try container.decode(Value.self, forKey: PathKey(lastKey))
    }
}

private struct PathKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
