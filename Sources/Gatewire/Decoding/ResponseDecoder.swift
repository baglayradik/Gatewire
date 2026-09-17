public import Alamofire
public import Foundation

/// Преобразует тело успешного ответа в значение.
///
/// Реализуйте протокол для форматов, которые не покрываются `Decodable`: ответов в обёртке,
/// XML, Protobuf и т.п. Ошибка, брошенная из ``decode(_:response:)``, приходит как
/// ``NetworkError/decodingFailed(_:data:)``.
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
    ///   - response: HTTP-ответ, например для чтения заголовков.
    func decode(_ data: Data, response: HTTPURLResponse) throws -> Output
}

/// Декодирует `Decodable`-значение с помощью `DataDecoder`, по умолчанию `JSONDecoder`.
public struct DecodableResponseDecoder<Value: Decodable & Sendable>: ResponseDecoder {
    /// Декодер данных.
    public let decoder: any DataDecoder

    /// Создаёт декодер.
    ///
    /// - Parameter decoder: Декодер данных. По умолчанию `JSONDecoder()`.
    public init(decoder: any DataDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func decode(_ data: Data, response: HTTPURLResponse) throws -> Value {
        try decoder.decode(Value.self, from: data)
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

    public func decode(_ data: Data, response: HTTPURLResponse) throws -> String {
        let encoding = encoding ?? response.textEncoding ?? .utf8
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
