public import Alamofire
public import Foundation

/// Декодированный ответ вместе с HTTP-метаданными.
public struct APIResponse<Value: Sendable>: Sendable {
    /// Декодированное значение.
    public let value: Value

    /// HTTP-ответ.
    public let response: HTTPURLResponse

    /// Исходное тело ответа.
    public let data: Data

    /// HTTP-код ответа.
    public var statusCode: Int { response.statusCode }

    /// Заголовки ответа.
    public var headers: HTTPHeaders { response.headers }

    /// Создаёт ответ.
    public init(value: Value, response: HTTPURLResponse, data: Data) {
        self.value = value
        self.response = response
        self.data = data
    }
}
