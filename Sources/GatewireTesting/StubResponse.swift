public import Foundation

/// Ответ, который заглушка возвращает вместо сервера.
public struct StubResponse: Sendable {
    /// HTTP-код ответа.
    public var statusCode: Int

    /// Заголовки ответа.
    public var headers: [String: String]

    /// Тело ответа.
    public var body: Data

    /// Ошибка сети вместо ответа, например `.notConnectedToInternet`.
    public var failure: URLError?

    /// Задержка перед ответом в секундах.
    public var delay: TimeInterval

    /// Создаёт ответ.
    public init(
        statusCode: Int = 200,
        headers: [String: String] = [:],
        body: Data = Data(),
        delay: TimeInterval = 0
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.failure = nil
        self.delay = delay
    }

    /// Ответ с JSON-телом из строки.
    public static func json(
        _ json: String,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) -> StubResponse {
        StubResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"].merging(headers) { _, custom in custom },
            body: Data(json.utf8)
        )
    }

    /// Ответ с закодированным в JSON значением.
    ///
    /// - Throws: Ошибку кодирования значения.
    public static func encoded(
        _ value: some Encodable,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> StubResponse {
        StubResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"].merging(headers) { _, custom in custom },
            body: try encoder.encode(value)
        )
    }

    /// Ответ с текстовым телом.
    public static func text(
        _ text: String,
        statusCode: Int = 200,
        contentType: String = "text/plain; charset=utf-8"
    ) -> StubResponse {
        StubResponse(statusCode: statusCode, headers: ["Content-Type": contentType], body: Data(text.utf8))
    }

    /// Ответ с произвольными данными.
    public static func data(
        _ data: Data,
        statusCode: Int = 200,
        contentType: String = "application/octet-stream"
    ) -> StubResponse {
        StubResponse(statusCode: statusCode, headers: ["Content-Type": contentType], body: data)
    }

    /// Ответ с указанным кодом и пустым телом.
    public static func status(_ statusCode: Int) -> StubResponse {
        StubResponse(statusCode: statusCode)
    }

    /// Ошибка сети вместо ответа.
    public static func failure(_ code: URLError.Code) -> StubResponse {
        var response = StubResponse()
        response.failure = URLError(code)
        return response
    }

    /// Перенаправление на другой адрес.
    public static func redirect(to location: URL, statusCode: Int = 302) -> StubResponse {
        StubResponse(statusCode: statusCode, headers: ["Location": location.absoluteString])
    }

    /// Тот же ответ с задержкой.
    ///
    /// - Parameter seconds: Задержка в секундах.
    public func delayed(by seconds: TimeInterval) -> StubResponse {
        var response = self
        response.delay = seconds
        return response
    }
}
