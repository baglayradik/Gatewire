public import Alamofire
public import Foundation

/// Преобразует тело успешного ответа в значение.
///
/// Реализуйте протокол для форматов, которые не покрываются `Decodable`: XML, Protobuf и т.п.
/// Для ответов в обёртке используйте ``EnvelopeDecoder`` или ``NestedResponseDecoder``.
///
/// Ошибка, брошенная из ``decode(_:context:)``, приходит как ``NetworkError/decodingFailed(_:data:)``.
/// Чтобы вернуть другую категорию ошибки — например, ошибку API внутри успешного ответа, —
/// бросьте готовую ``NetworkError``: она передаётся без изменений.
///
/// ```swift
/// let text = try await client.request(PageRouter.robots, decoder: .string)
/// ```
public protocol ResponseDecoder<Output>: Sendable {
    /// Тип результата декодирования.
    associatedtype Output: Sendable

    /// Декодирует тело ответа.
    ///
    /// - Parameters:
    ///   - data: Тело ответа. Для ответа без тела — пустые данные.
    ///   - context: HTTP-ответ и декодер данных, выбранный для эндпоинта.
    func decode(_ data: Data, context: ResponseDecodingContext) throws -> Output
}

/// Данные, доступные ``ResponseDecoder`` при декодировании ответа.
public struct ResponseDecodingContext: Sendable {
    /// HTTP-ответ, например для чтения заголовков.
    public let response: HTTPURLResponse

    /// Декодер данных эндпоинта: ``Endpoint/decoder``, а если он не задан — ``APIConfiguration/decoder``.
    public let dataDecoder: any DataDecoder

    /// Создаёт контекст.
    public init(response: HTTPURLResponse, dataDecoder: any DataDecoder) {
        self.response = response
        self.dataDecoder = dataDecoder
    }
}

/// Декодирует `Decodable`-значение из тела ответа.
public struct DecodableResponseDecoder<Value: Decodable & Sendable>: ResponseDecoder {
    /// Декодер данных. Если `nil`, используется ``ResponseDecodingContext/dataDecoder``.
    public let decoder: (any DataDecoder)?

    /// Создаёт декодер.
    ///
    /// - Parameter decoder: Декодер данных. По умолчанию `nil` — декодер эндпоинта или клиента.
    public init(decoder: (any DataDecoder)? = nil) {
        self.decoder = decoder
    }

    public func decode(_ data: Data, context: ResponseDecodingContext) throws -> Value {
        try (decoder ?? context.dataDecoder).decode(Value.self, from: data)
    }
}

/// Декодирует тело ответа в строку.
public struct StringResponseDecoder: ResponseDecoder {
    /// Кодировка текста. Если `nil`, берётся из заголовка `Content-Type`, а при его отсутствии — UTF-8.
    public let encoding: String.Encoding?

    /// Создаёт декодер.
    ///
    /// - Parameter encoding: Кодировка текста. По умолчанию `nil` — определяется по ответу.
    public init(encoding: String.Encoding? = nil) {
        self.encoding = encoding
    }

    public func decode(_ data: Data, context: ResponseDecodingContext) throws -> String {
        let encoding = encoding ?? context.response.textEncoding ?? .utf8
        guard let string = String(data: data, encoding: encoding) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Тело ответа не является строкой в кодировке \(encoding)."
                )
            )
        }
        return string
    }
}

extension ResponseDecoder where Self == StringResponseDecoder {
    /// Декодер тела ответа в строку с кодировкой из ответа или UTF-8.
    public static var string: StringResponseDecoder { StringResponseDecoder() }
}

extension HTTPURLResponse {
    fileprivate var textEncoding: String.Encoding? {
        guard let name = textEncodingName else { return nil }

        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)

        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }

        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}
