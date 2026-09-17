import Foundation
import Gatewire
import Testing

/// Потокобезопасный контейнер для значений, которые обработчик запроса передаёт тесту.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    var current: Value {
        withValue { $0 }
    }
}

/// Эндпоинт, все параметры которого задаются в тесте.
struct TestEndpoint: Endpoint {
    var baseURL: URL
    var path = "items"
    var method: HTTPMethod = .get
    var task: RequestTask = .plain
    var headers: HTTPHeaders = [:]
    var timeoutInterval: TimeInterval?
    var jsonEncoder = JSONEncoder()
    var formEncoderFactory: @Sendable () -> URLEncodedFormEncoder = { URLEncodedFormEncoder() }
    var decoder: (any DataDecoder)?

    var formEncoder: URLEncodedFormEncoder { formEncoderFactory() }
}

/// Клиент, запросы которого обрабатывает `MockURLProtocol`, и базовый адрес с уникальным хостом.
struct MockServer: Sendable {
    let client: APIClient
    let baseURL: URL
    let lastRequest = Locked<URLRequest?>(nil)

    init(handler: @escaping MockURLProtocol.Handler = { request in try MockServer.respond(to: request) }) {
        self.init(configure: { _ in }, handler: handler)
    }

    init(
        configure: (inout APIConfiguration) -> Void,
        handler: @escaping MockURLProtocol.Handler = { request in try MockServer.respond(to: request) }
    ) {
        let host = "\(UUID().uuidString.lowercased()).gatewire.test"
        let lastRequest = lastRequest
        MockURLProtocol.register(host: host) { request in
            lastRequest.withValue { $0 = request }
            return try await handler(request)
        }

        baseURL = URL(string: "https://\(host)/v1")!
        client = APIClient {
            $0.sessionConfiguration = {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [MockURLProtocol.self]
                return configuration
            }
            configure(&$0)
        }
    }

    func endpoint(
        path: String = "items",
        method: HTTPMethod = .get,
        task: RequestTask = .plain,
        headers: HTTPHeaders = [:]
    ) -> TestEndpoint {
        TestEndpoint(baseURL: baseURL, path: path, method: method, task: task, headers: headers)
    }

    static func respond(
        to request: URLRequest,
        status: Int = 200,
        json: String = "{}",
        headers: [String: String] = ["Content-Type": "application/json"]
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
        return (response, Data(json.utf8))
    }
}

/// Выполняет операцию и возвращает брошенную `NetworkError` или `nil`, если ошибки не было.
func networkError(_ operation: () async throws(NetworkError) -> Void) async -> NetworkError? {
    do {
        try await operation()
        return nil
    } catch {
        return error
    }
}

struct UserDTO: Codable, Equatable, Sendable {
    let id: Int
    let fullName: String
}
