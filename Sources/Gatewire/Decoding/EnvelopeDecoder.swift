public import Alamofire
public import Foundation

/// Обёртка ответа API, из которой извлекаются полезные данные.
///
/// Подходит для API, которые возвращают данные внутри общей структуры и могут сообщать
/// об ошибке в теле успешного HTTP-ответа:
///
/// ```swift
/// struct ServerEnvelope<Payload: Decodable & Sendable>: ResponseEnvelope {
///     let success: Bool
///     let data: Payload?
///     let error: ServerError?
///
///     func unwrap() throws -> Payload {
///         guard success, let data else { throw error ?? ServerError.unknown }
///         return data
///     }
/// }
///
/// let user = try await client.request(
///     UserRouter.profile,
///     decoder: .envelope(ServerEnvelope<UserDTO>.self)
/// )
/// ```
public protocol ResponseEnvelope<Payload>: Decodable, Sendable {
    /// Тип полезных данных.
    associatedtype Payload: Sendable

    /// Возвращает полезные данные.
    ///
    /// Брошенная ошибка приходит как ``NetworkError/api(_:response:data:)``.
    func unwrap() throws -> Payload
}

/// Декодирует ``ResponseEnvelope`` и возвращает его полезные данные.
public struct EnvelopeDecoder<Envelope: ResponseEnvelope>: ResponseDecoder {
    /// Декодер данных. Если `nil`, используется ``ResponseDecodingContext/dataDecoder``.
    public let decoder: (any DataDecoder)?

    /// Создаёт декодер.
    ///
    /// - Parameters:
    ///   - type: Тип обёртки.
    ///   - decoder: Декодер данных. По умолчанию `nil` — декодер эндпоинта или клиента.
    public init(_ type: Envelope.Type = Envelope.self, decoder: (any DataDecoder)? = nil) {
        self.decoder = decoder
    }

    public func decode(_ data: Data, context: ResponseDecodingContext) throws -> Envelope.Payload {
        let envelope = try (decoder ?? context.dataDecoder).decode(Envelope.self, from: data)
        do {
            return try envelope.unwrap()
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.api(error, response: context.response, data: data)
        }
    }
}

extension ResponseDecoder {
    /// Декодер, извлекающий полезные данные из обёртки ответа.
    ///
    /// - Parameters:
    ///   - type: Тип обёртки.
    ///   - decoder: Декодер данных. По умолчанию `nil` — декодер эндпоинта или клиента.
    public static func envelope<Envelope>(
        _ type: Envelope.Type,
        decoder: (any DataDecoder)? = nil
    ) -> Self where Self == EnvelopeDecoder<Envelope> {
        EnvelopeDecoder(type, decoder: decoder)
    }
}
