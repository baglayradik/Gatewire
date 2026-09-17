public import Alamofire
public import Foundation

/// Параметры и тело HTTP-запроса.
///
/// Во всех вариантах, кроме ``raw(_:contentType:)`` и ``multipart(_:)``, используются кодировщики Alamofire:
/// параметры — любые `Encodable`-типы, в том числе словари, заголовок `Content-Type` выставляется,
/// только если он ещё не задан в ``Endpoint/headers``.
public enum RequestTask: Sendable {
    /// Запрос без параметров и тела.
    case plain

    /// Параметры в строке запроса (`?page=2&sort=name`), независимо от HTTP-метода.
    case query(any Encodable & Sendable)

    /// JSON-тело. Кодируется ``Endpoint/jsonEncoder``, `Content-Type: application/json`.
    case json(any Encodable & Sendable)

    /// Тело `application/x-www-form-urlencoded`.
    case form(any Encodable & Sendable)

    /// Параметры в строке запроса и JSON-тело одновременно.
    case queryAndJSON(query: any Encodable & Sendable, body: any Encodable & Sendable)

    /// Готовое тело с указанным `Content-Type`, например XML или Protobuf.
    case raw(Data, contentType: String)

    /// Тело `multipart/form-data`, например для загрузки файлов.
    ///
    /// Замыкание получает `MultipartFormData`, в который нужно добавить части запроса.
    /// ``APIClient`` отправляет такой запрос как upload-запрос Alamofire.
    case multipart(@Sendable (MultipartFormData) -> Void)

    /// Кодирует параметры и тело в запрос.
    ///
    /// Для ``multipart(_:)`` запрос возвращается без изменений: тело формирует ``APIClient`` при отправке.
    ///
    /// - Parameters:
    ///   - request: Запрос, в который добавляются параметры и тело.
    ///   - jsonEncoder: Кодировщик JSON-тела.
    /// - Throws: ``NetworkError/encodingFailed(_:)``, если не удалось закодировать параметры или тело.
    public func encode(
        into request: URLRequest,
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) throws -> URLRequest {
        switch self {
        case .plain, .multipart:
            return request

        case let .query(parameters):
            return try Self.encode(
                parameters,
                using: URLEncodedFormParameterEncoder(destination: .queryString),
                into: request
            )

        case let .json(body):
            return try Self.encode(
                body,
                using: JSONParameterEncoder(encoder: jsonEncoder),
                into: request
            )

        case let .form(parameters):
            return try Self.encode(
                parameters,
                using: URLEncodedFormParameterEncoder(destination: .httpBody),
                into: request
            )

        case let .queryAndJSON(query, body):
            let requestWithQuery = try Self.encode(
                query,
                using: URLEncodedFormParameterEncoder(destination: .queryString),
                into: request
            )
            return try Self.encode(
                body,
                using: JSONParameterEncoder(encoder: jsonEncoder),
                into: requestWithQuery
            )

        case let .raw(data, contentType):
            var request = request
            request.httpBody = data
            if request.headers["Content-Type"] == nil {
                request.headers.update(.contentType(contentType))
            }
            return request
        }
    }

    private static func encode<Parameters: Encodable & Sendable>(
        _ parameters: Parameters,
        using encoder: some ParameterEncoder,
        into request: URLRequest
    ) throws -> URLRequest {
        do {
            return try encoder.encode(parameters, into: request)
        } catch {
            throw NetworkError.encodingFailed(error)
        }
    }
}
