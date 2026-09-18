import Foundation
import Gatewire
import GatewireTesting
import Testing

@Suite("StubNetwork")
struct StubNetworkTests {
    @Test("Заглушка по эндпоинту отвечает на его запрос")
    func stubsEndpoint() async throws {
        let network = StubNetwork()
        network.on(UserRouter.profile).respond(json: #"{"id": 1, "name": "Test"}"#)

        let user = try await network.makeClient().request(UserRouter.profile, as: User.self)

        #expect(user == User(id: 1, name: "Test"))
        #expect(network.requests(to: UserRouter.profile).count == 1)
    }

    @Test("Параметры строки запроса учитываются при сопоставлении, порядок — нет")
    func matchesQueryIgnoringOrder() async throws {
        let network = StubNetwork()
        network.on(UserRouter.search(query: "swift", page: 2)).respond(json: "[]")
        let client = network.makeClient()

        let found: [User] = try await client.request(UserRouter.search(query: "swift", page: 2))
        #expect(found.isEmpty)

        let error = await networkError { () async throws(NetworkError) in
            try await client.send(UserRouter.search(query: "swift", page: 3))
        }
        #expect(error?.statusCode == 404)
        #expect(network.unmatchedRequests.count == 1)
    }

    @Test("Сети с одинаковыми адресами изолированы друг от друга")
    func networksAreIsolated() async throws {
        let first = StubNetwork()
        let second = StubNetwork()
        first.on(UserRouter.profile).respond(json: #"{"id": 1, "name": "First"}"#)
        second.on(UserRouter.profile).respond(json: #"{"id": 2, "name": "Second"}"#)

        async let firstUser = first.makeClient().request(UserRouter.profile, as: User.self)
        async let secondUser = second.makeClient().request(UserRouter.profile, as: User.self)

        #expect(try await firstUser.name == "First")
        #expect(try await secondUser.name == "Second")
        #expect(first.requests.count == 1)
        #expect(second.requests.count == 1)
    }

    @Test("Ответы выдаются по очереди, последний повторяется")
    func responseSequence() async throws {
        let network = StubNetwork()
        let route = network.on(UserRouter.profile).respond(with: .status(503), .json(#"{"id": 1, "name": "A"}"#))
        let client = network.makeClient()

        let first = await networkError { () async throws(NetworkError) in
            try await client.send(UserRouter.profile)
        }
        #expect(first?.statusCode == 503)

        _ = try await client.request(UserRouter.profile, as: User.self)
        _ = try await client.request(UserRouter.profile, as: User.self)

        #expect(route.callCount == 3)
    }

    @Test("Заглушка, добавленная последней, важнее")
    func lastRouteWins() async throws {
        let network = StubNetwork()
        network.on(path: "/v1/me").respond(json: #"{"id": 1, "name": "Default"}"#)
        network.on(UserRouter.profile).respond(json: #"{"id": 2, "name": "Override"}"#)

        let user = try await network.makeClient().request(UserRouter.profile, as: User.self)

        #expect(user.name == "Override")
    }

    @Test("Динамический ответ видит запрос")
    func dynamicResponse() async throws {
        let network = StubNetwork()
        network.on(UserRouter.create(User(id: 0, name: "New"))).respond { request in
            let body = try JSONDecoder().decode(User.self, from: request.httpBody ?? Data())
            return try .encoded(User(id: 42, name: body.name), statusCode: 201)
        }

        let created = try await network.makeClient().request(
            UserRouter.create(User(id: 0, name: "New")),
            as: User.self
        )

        #expect(created == User(id: 42, name: "New"))
    }

    @Test("Записанный запрос содержит тело и не содержит служебного заголовка")
    func recordedRequest() async throws {
        let network = StubNetwork()
        network.on(UserRouter.create(User(id: 0, name: "New"))).respond(statusCode: 201)

        try await network.makeClient().send(UserRouter.create(User(id: 0, name: "New")))

        let request = try #require(network.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(try JSONDecoder().decode(User.self, from: request.httpBody ?? Data()).name == "New")
        #expect(request.allHTTPHeaderFields?.keys.contains { $0.lowercased().contains("stub") } == false)
    }

    @Test("Ошибка сети из заглушки")
    func networkFailure() async throws {
        let network = StubNetwork()
        network.on(UserRouter.profile).fail(with: .notConnectedToInternet)

        let error = await networkError { () async throws(NetworkError) in
            try await network.makeClient().send(UserRouter.profile)
        }

        guard case let .transport(urlError) = error else {
            Issue.record("Ожидалась transport, получено \(String(describing: error))")
            return
        }
        #expect(urlError.code == .notConnectedToInternet)
    }

    @Test("Задержка ответа позволяет проверить отмену")
    func delayedResponseCanBeCancelled() async throws {
        let network = StubNetwork()
        network.on(UserRouter.profile).respond(with: StubResponse.status(200).delayed(by: 10))
        let client = network.makeClient()

        let task = Task { () async -> NetworkError? in
            await networkError { () async throws(NetworkError) in
                try await client.send(UserRouter.profile)
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let error = await task.value
        guard case .cancelled = error else {
            Issue.record("Ожидалась cancelled, получено \(String(describing: error))")
            return
        }
    }

    @Test("Свой ответ на запросы без заглушки")
    func customUnmatchedResponse() async throws {
        let network = StubNetwork()
        network.unmatchedResponse = .status(418)

        let error = await networkError { () async throws(NetworkError) in
            try await network.makeClient().send(UserRouter.profile)
        }

        #expect(error?.statusCode == 418)
    }

    @Test("reset удаляет заглушки и записанные запросы")
    func reset() async throws {
        let network = StubNetwork()
        network.on(UserRouter.profile).respond(json: #"{"id": 1, "name": "A"}"#)
        let client = network.makeClient()
        _ = try await client.request(UserRouter.profile, as: User.self)

        network.reset()

        #expect(network.requests.isEmpty)
        let error = await networkError { () async throws(NetworkError) in
            try await client.send(UserRouter.profile)
        }
        #expect(error?.statusCode == 404)
    }

    @Test("Повторы в клиенте из makeClient выключены, но их можно включить")
    func retriesDisabledByDefault() async throws {
        let network = StubNetwork()
        let route = network.on(UserRouter.profile).respond(with: .status(503), .status(200))

        _ = await networkError { () async throws(NetworkError) in
            try await network.makeClient().send(UserRouter.profile)
        }
        #expect(route.callCount == 1)

        let retrying = network.makeClient {
            $0.retry = .default
            $0.retry.exponentialBackoffScale = 0.001
        }
        try await retrying.send(UserRouter.profile)
        #expect(route.callCount == 2)
    }

    @Test("Перенаправление из заглушки")
    func redirect() async throws {
        let network = StubNetwork()
        let target = try #require(URL(string: "https://api.example.com/v2/me"))
        network.on(UserRouter.profile).respond(with: .redirect(to: target))
        network.on(.get, path: "/v2/me").respond(json: #"{"id": 7, "name": "Moved"}"#)

        let user = try await network.makeClient().request(UserRouter.profile, as: User.self)

        #expect(user.name == "Moved")
        #expect(network.requests.map { $0.url?.path } == ["/v1/me", "/v2/me"])
    }

    @Test("Скачивание в файл работает через заглушку")
    func download() async throws {
        let network = StubNetwork()
        network.on(UserRouter.avatar).respond(with: .data(Data("image".utf8), contentType: "image/png"))
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("gatewire-testing-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: destination) }

        try await network.makeClient().download(UserRouter.avatar, to: destination)

        #expect(try Data(contentsOf: destination) == Data("image".utf8))
    }
}

@Suite("StubCredentialRefresher")
struct StubCredentialRefresherTests {
    private let expired = OAuth2Credential(
        accessToken: "old",
        refreshToken: "refresh",
        expiresAt: Date().addingTimeInterval(-10)
    )

    @Test("Обновляет токен и считает вызовы")
    func refreshesToken() async throws {
        let network = StubNetwork()
        network.on(where: { $0.value(forHTTPHeaderField: "Authorization") == "Bearer new" })
            .respond(json: #"{"id": 1, "name": "A"}"#)
        let refresher = StubCredentialRefresher(returning: OAuth2Credential(accessToken: "new"))
        let client = network.makeClient {
            $0.auth = .refreshable(store: InMemoryCredentialStore(expired), refresher: refresher)
        }

        _ = try await client.request(UserRouter.profile, as: User.self)

        #expect(await refresher.refreshCount == 1)
        #expect(await refresher.lastRefreshedCredential?.accessToken == "old")
    }

    @Test("Результаты выдаются по очереди")
    func resultsSequence() async throws {
        struct RefreshError: Error {}
        let refresher = StubCredentialRefresher<OAuth2Credential>(results: [
            .failure(RefreshError()),
            .success(OAuth2Credential(accessToken: "second")),
        ])

        await #expect(throws: RefreshError.self) {
            try await refresher.refresh(expired)
        }
        #expect(try await refresher.refresh(expired).accessToken == "second")
        #expect(try await refresher.refresh(expired).accessToken == "second")
        #expect(await refresher.refreshCount == 3)
    }
}

// MARK: - Вспомогательное

private struct User: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

private enum UserRouter: Endpoint {
    case profile
    case search(query: String, page: Int)
    case create(User)
    case avatar

    var baseURL: URL { URL(string: "https://api.example.com/v1")! }

    var path: String {
        switch self {
        case .profile: "me"
        case .search: "users"
        case .create: "users"
        case .avatar: "me/avatar"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .create: .post
        default: .get
        }
    }

    var task: RequestTask {
        switch self {
        case let .search(query, page): .query(SearchQuery(q: query, page: page))
        case let .create(user): .json(user)
        default: .plain
        }
    }
}

private struct SearchQuery: Encodable, Sendable {
    let q: String
    let page: Int
}

private func networkError(_ operation: () async throws(NetworkError) -> Void) async -> NetworkError? {
    do {
        try await operation()
        return nil
    } catch {
        return error
    }
}
