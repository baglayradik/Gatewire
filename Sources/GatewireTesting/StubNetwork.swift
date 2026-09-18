public import Foundation
public import Gatewire

/// Подменённая сеть для тестов: запросы клиента не уходят в интернет, а обрабатываются заглушками.
///
/// Каждый экземпляр изолирован: тесты с одинаковыми адресами могут выполняться параллельно.
///
/// ```swift
/// @Test func loadsProfile() async throws {
///     let network = StubNetwork()
///     network.on(UserRouter.profile).respond(json: #"{"id": 1, "name": "Test"}"#)
///
///     let client = network.makeClient()
///     let profile = try await client.request(UserRouter.profile, as: UserDTO.self)
///
///     #expect(profile.id == 1)
///     #expect(network.requests(to: UserRouter.profile).count == 1)
/// }
/// ```
public final class StubNetwork: Sendable {
    /// Идентификатор сети, по которому перехваченные запросы находят свои заглушки.
    let id = UUID().uuidString

    private let routes = LockedValue<[StubRoute]>([])
    private let recordedRequests = LockedValue<[URLRequest]>([])
    private let recordedUnmatchedRequests = LockedValue<[URLRequest]>([])
    private let unmatched = LockedValue(StubResponse.json(#"{"error": "Нет заглушки для запроса"}"#, statusCode: 404))

    /// Создаёт пустую сеть. Запросы без подходящей заглушки получают ``unmatchedResponse``.
    public init() {
        StubURLProtocol.register(self)
    }

    deinit {
        StubURLProtocol.unregister(id: id)
    }

    // MARK: - Клиенты

    /// Фабрика конфигурации `URLSession`, направляющая запросы в эту сеть.
    ///
    /// Нужна, если запросы выполняет не ``makeClient(_:)``, а, например, `OAuth2TokenRefresher`.
    public var sessionConfiguration: @Sendable () -> URLSessionConfiguration {
        let id = id
        return {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubURLProtocol.self]
            configuration.httpAdditionalHeaders = [StubURLProtocol.networkHeader: id]
            return configuration
        }
    }

    /// Создаёт клиент, запросы которого обрабатывает эта сеть.
    ///
    /// Повторы запросов в таком клиенте по умолчанию отключены, чтобы тесты не ждали задержек
    /// между ними. Включить их можно в замыкании настройки.
    ///
    /// - Parameter configure: Настройка клиента, как в `APIClient.init(_:)`.
    public func makeClient(_ configure: (inout APIConfiguration) -> Void = { _ in }) -> APIClient {
        APIClient { configuration in
            configuration.sessionConfiguration = sessionConfiguration
            configuration.retry = .disabled
            configure(&configuration)
        }
    }

    // MARK: - Заглушки

    /// Перехватывает запросы, совпадающие с запросом эндпоинта по методу, адресу и параметрам строки запроса.
    ///
    /// Тело и заголовки запроса не сравниваются. Если подходят несколько правил,
    /// срабатывает добавленное последним.
    @discardableResult
    public func on(_ endpoint: some Endpoint) -> StubRoute {
        let expected: URLRequest
        do {
            expected = try endpoint.asURLRequest()
        } catch {
            preconditionFailure("Не удалось собрать запрос эндпоинта для заглушки: \(error)")
        }

        return on { request in
            request.httpMethod == expected.httpMethod && Self.isSameResource(request.url, expected.url)
        }
    }

    /// Перехватывает запросы с указанным путём, например `"/v1/users/42"`, на любом хосте.
    ///
    /// - Parameters:
    ///   - method: HTTP-метод или `nil` для любого метода.
    ///   - path: Путь запроса без строки параметров.
    @discardableResult
    public func on(_ method: HTTPMethod? = nil, path: String) -> StubRoute {
        on { request in
            (method == nil || request.httpMethod == method?.rawValue) && request.url?.path == path
        }
    }

    /// Перехватывает запросы, для которых условие возвращает `true`.
    @discardableResult
    public func on(where predicate: @escaping @Sendable (URLRequest) -> Bool) -> StubRoute {
        let route = StubRoute(matches: predicate)
        routes.withValue { $0.append(route) }
        return route
    }

    /// Ответ на запросы без подходящей заглушки. По умолчанию `404` с описанием в теле.
    public var unmatchedResponse: StubResponse {
        get { unmatched.withValue { $0 } }
        set { unmatched.withValue { $0 = newValue } }
    }

    // MARK: - Записанные запросы

    /// Все запросы, дошедшие до сети, в порядке поступления. Тело запроса доступно в `httpBody`.
    public var requests: [URLRequest] {
        recordedRequests.withValue { $0 }
    }

    /// Запросы, для которых не нашлось заглушки.
    public var unmatchedRequests: [URLRequest] {
        recordedUnmatchedRequests.withValue { $0 }
    }

    /// Запросы, совпадающие с запросом эндпоинта по методу, адресу и параметрам строки запроса.
    public func requests(to endpoint: some Endpoint) -> [URLRequest] {
        guard let expected = try? endpoint.asURLRequest() else { return [] }

        return requests.filter { request in
            request.httpMethod == expected.httpMethod && Self.isSameResource(request.url, expected.url)
        }
    }

    /// Удаляет все заглушки и записанные запросы.
    public func reset() {
        routes.withValue { $0.removeAll() }
        recordedRequests.withValue { $0.removeAll() }
        recordedUnmatchedRequests.withValue { $0.removeAll() }
    }

    // MARK: - Обработка запросов

    func response(for request: URLRequest) async throws -> StubResponse {
        recordedRequests.withValue { $0.append(request) }

        let route = routes.withValue { routes in
            routes.last { $0.matches(request) }
        }
        guard let route else {
            recordedUnmatchedRequests.withValue { $0.append(request) }
            return unmatchedResponse
        }

        return try await route.response(for: request)
    }

    private static func isSameResource(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs,
              let left = URLComponents(url: lhs, resolvingAgainstBaseURL: true),
              let right = URLComponents(url: rhs, resolvingAgainstBaseURL: true)
        else {
            return false
        }

        let leftQuery = (left.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" }.sorted()
        let rightQuery = (right.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" }.sorted()

        return left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && left.port == right.port
            && left.path == right.path
            && leftQuery == rightQuery
    }
}
