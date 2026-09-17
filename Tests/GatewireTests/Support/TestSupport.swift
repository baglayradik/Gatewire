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
    var authorization: AuthorizationRequirement = .inherit
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

    /// Все запросы, которые дошли до сети, в порядке отправки.
    let requests = Locked<[URLRequest]>([])

    init(handler: @escaping MockURLProtocol.Handler = { request in try MockServer.respond(to: request) }) {
        self.init(configure: { _ in }, handler: handler)
    }

    init(
        configure: (inout APIConfiguration) -> Void,
        handler: @escaping MockURLProtocol.Handler = { request in try MockServer.respond(to: request) }
    ) {
        let lastRequest = lastRequest
        let requests = requests
        let (host, baseURL) = MockServer.registerHost { request in
            lastRequest.withValue { $0 = request }
            requests.withValue { $0.append(request) }
            return try await handler(request)
        }
        _ = host

        self.baseURL = baseURL
        client = APIClient {
            $0.sessionConfiguration = MockServer.sessionConfiguration
            configure(&$0)
        }
    }

    /// Регистрирует уникальный хост в `MockURLProtocol` и возвращает его вместе с базовым адресом.
    static func registerHost(handler: @escaping MockURLProtocol.Handler) -> (host: String, baseURL: URL) {
        let host = "\(UUID().uuidString.lowercased()).gatewire.test"
        MockURLProtocol.register(host: host, handler: handler)

        return (host, URL(string: "https://\(host)/v1")!)
    }

    static let sessionConfiguration: @Sendable () -> URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    func endpoint(
        path: String = "items",
        method: HTTPMethod = .get,
        task: RequestTask = .plain,
        headers: HTTPHeaders = [:],
        authorization: AuthorizationRequirement = .inherit
    ) -> TestEndpoint {
        TestEndpoint(
            baseURL: baseURL,
            path: path,
            method: method,
            task: task,
            headers: headers,
            authorization: authorization
        )
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

/// Собирает события авторизации, пока идёт тест.
final class AuthEventRecorder: Sendable {
    private let events = Locked<[AuthEvent]>([])
    private let task = Locked<Task<Void, Never>?>(nil)

    init(_ controller: AuthController) {
        let events = events
        let stream = controller.events()
        task.withValue { task in
            task = Task {
                for await event in stream {
                    events.withValue { $0.append(event) }
                }
            }
        }
    }

    deinit {
        task.withValue { $0?.cancel() }
    }

    var recorded: [AuthEvent] {
        events.current
    }

    /// Ждёт событие, подходящее под условие, и возвращает его или `nil` по истечении времени.
    func waitForEvent(
        timeout: TimeInterval = 2,
        where predicate: @escaping @Sendable (AuthEvent) -> Bool
    ) async -> AuthEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = events.current.first(where: predicate) {
                return event
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return nil
    }
}

struct UserDTO: Codable, Equatable, Sendable {
    let id: Int
    let fullName: String
}
