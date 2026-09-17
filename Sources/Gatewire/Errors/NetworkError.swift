public import Foundation

/// Ошибка выполнения запроса через ``APIClient``.
public enum NetworkError: Error, Sendable {
    /// Не удалось собрать запрос: некорректный URL, тело в GET-запросе или ошибка в ``Endpoint/asURLRequest()``.
    case invalidRequest(any Error)

    /// Не удалось закодировать параметры или тело запроса.
    case encodingFailed(any Error)

    /// Ошибка транспорта: нет сети, таймаут, проблемы с TLS и т.п.
    case transport(URLError)

    /// Сервер вернул код ответа вне ``APIConfiguration/acceptableStatusCodes``,
    /// и ``APIConfiguration/errorMapper`` не распознал тело ошибки.
    case unacceptableStatusCode(response: HTTPURLResponse, data: Data)

    /// Сервер вернул ошибку, которую распознал ``APIConfiguration/errorMapper``.
    case api(any Error, response: HTTPURLResponse, data: Data)

    /// Не удалось декодировать тело успешного ответа.
    case decodingFailed(any Error, data: Data)

    /// Запрос отменён, например вместе с задачей, в которой он выполнялся.
    case cancelled

    /// Прочая ошибка, не попавшая в другие категории.
    case underlying(any Error)
}

extension NetworkError {
    /// HTTP-код ответа, если сервер успел ответить.
    public var statusCode: Int? {
        switch self {
        case let .unacceptableStatusCode(response, _), let .api(_, response, _):
            response.statusCode
        default:
            nil
        }
    }

    /// Тело ответа, если оно было получено.
    public var responseData: Data? {
        switch self {
        case let .unacceptableStatusCode(_, data), let .api(_, _, data), let .decodingFailed(_, data):
            data
        default:
            nil
        }
    }
}
