import Foundation
import Gatewire
import Testing

@Suite("Обновление токена")
struct RefreshAuthTests {
    /// Сервер отвечает 200 только на запросы с актуальным токеном, остальным — 401.
    private func server(
        store: InMemoryCredentialStore<OAuth2Credential>,
        refresher: some CredentialRefresher<OAuth2Credential>,
        validToken: String = "new-token"
    ) -> MockServer {
        MockServer(
            configure: { configuration in
                configuration.auth = .refreshable(store: store, refresher: refresher)
            },
            handler: { request in
                let authorization = request.value(forHTTPHeaderField: "Authorization")
                let status = authorization == "Bearer \(validToken)" ? 200 : 401
                return try MockServer.respond(to: request, status: status, json: #"{"ok": true}"#)
            }
        )
    }

    private func expired(_ token: String = "old-token") -> OAuth2Credential {
        OAuth2Credential(
            accessToken: token,
            refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(-10)
        )
    }

    private func valid(_ token: String = "new-token") -> OAuth2Credential {
        OAuth2Credential(
            accessToken: token,
            refreshToken: "refresh-2",
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    @Test("signIn сохраняет учётные данные, применяет их и сообщает событие")
    func signInAppliesCredential() async throws {
        let store = InMemoryCredentialStore<OAuth2Credential>()
        let refresher = CountingRefresher(result: .success(valid()))
        let server = server(store: store, refresher: refresher)
        let recorder = AuthEventRecorder(server.client.auth)

        try await server.client.auth.signIn(with: valid())
        try await server.client.send(server.endpoint(authorization: .required))

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer new-token")
        #expect(try await store.load()?.accessToken == "new-token")
        #expect(await server.client.auth.isAuthenticated())
        #expect(await server.client.auth.credential(as: OAuth2Credential.self)?.accessToken == "new-token")
        #expect(await recorder.waitForEvent { if case .signedIn = $0 { true } else { false } } != nil)
        #expect(await refresher.count == 0)
    }

    @Test("Учётные данные читаются из хранилища при первом запросе")
    func credentialIsLoadedFromStore() async throws {
        let store = InMemoryCredentialStore(valid())
        let refresher = CountingRefresher(result: .success(valid()))
        let server = server(store: store, refresher: refresher)

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer new-token")
        #expect(await refresher.count == 0)
    }

    @Test("Истёкший токен обновляется до отправки запроса")
    func expiredCredentialIsRefreshedBeforeRequest() async throws {
        let store = InMemoryCredentialStore(expired())
        let refresher = CountingRefresher(result: .success(valid()))
        let server = server(store: store, refresher: refresher)
        let recorder = AuthEventRecorder(server.client.auth)

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(await refresher.count == 1)
        #expect(server.requests.current.count == 1)
        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer new-token")
        #expect(try await store.load()?.accessToken == "new-token")
        #expect(await recorder.waitForEvent { if case .refreshed = $0 { true } else { false } } != nil)
    }

    @Test("50 параллельных запросов с истёкшим токеном вызывают одно обновление")
    func parallelRequestsRefreshOnce() async throws {
        let store = InMemoryCredentialStore(expired())
        let refresher = CountingRefresher(result: .success(valid()), delayMilliseconds: 50)
        let server = server(store: store, refresher: refresher)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    try await server.client.send(server.endpoint(authorization: .required))
                }
            }
            try await group.waitForAll()
        }

        #expect(await refresher.count == 1)
        #expect(server.requests.current.count == 50)
        let tokens = Set(server.requests.current.map { $0.value(forHTTPHeaderField: "Authorization") })
        #expect(tokens == ["Bearer new-token"])
    }

    @Test("Ответ 401 приводит к обновлению токена и повтору запроса")
    func unauthorizedResponseTriggersRefreshAndRetry() async throws {
        // Токен не истёк по времени, но сервер его отклоняет.
        let rejected = OAuth2Credential(
            accessToken: "rejected-token",
            refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let store = InMemoryCredentialStore(rejected)
        let refresher = CountingRefresher(result: .success(valid()))
        let server = server(store: store, refresher: refresher)

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(await refresher.count == 1)
        #expect(server.requests.current.count == 2)
        #expect(server.requests.current.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer rejected-token",
            "Bearer new-token",
        ])
    }

    @Test("Ошибка обновления приходит как authenticationFailed и сообщается событием")
    func refreshFailurePropagates() async throws {
        let store = InMemoryCredentialStore(expired())
        let refresher = CountingRefresher(result: .failure(OAuth2Error.server(
            code: "invalid_grant",
            description: "refresh token expired",
            statusCode: 400
        )))
        let server = server(store: store, refresher: refresher)
        let recorder = AuthEventRecorder(server.client.auth)

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(authorization: .required))
        }

        guard case let .authenticationFailed(underlying) = error else {
            Issue.record("Ожидалась authenticationFailed, получено \(String(describing: error))")
            return
        }
        #expect(underlying as? OAuth2Error == .server(
            code: "invalid_grant",
            description: "refresh token expired",
            statusCode: 400
        ))
        #expect(server.requests.current.isEmpty)
        #expect(await recorder.waitForEvent { if case .refreshFailed = $0 { true } else { false } } != nil)
    }

    @Test("При ошибке обновления падают все ожидающие запросы")
    func refreshFailureFailsAllPendingRequests() async throws {
        let store = InMemoryCredentialStore(expired())
        let refresher = CountingRefresher(
            result: .failure(OAuth2Error.missingRefreshToken),
            delayMilliseconds: 50
        )
        let server = server(store: store, refresher: refresher)

        let errors = await withTaskGroup(of: NetworkError?.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await networkError { () async throws(NetworkError) in
                        try await server.client.send(server.endpoint(authorization: .required))
                    }
                }
            }
            return await group.reduce(into: [NetworkError?]()) { $0.append($1) }
        }

        #expect(errors.count == 10)
        #expect(errors.allSatisfy { error in
            if case .authenticationFailed = error { true } else { false }
        })
        #expect(await refresher.count == 1)
    }

    @Test("signOut удаляет учётные данные из хранилища и из клиента")
    func signOutClearsCredential() async throws {
        let store = InMemoryCredentialStore(valid())
        let refresher = CountingRefresher(result: .success(valid()))
        let server = server(store: store, refresher: refresher)
        let recorder = AuthEventRecorder(server.client.auth)

        try await server.client.auth.signOut()

        #expect(try await store.load() == nil)
        #expect(await server.client.auth.isAuthenticated() == false)
        #expect(await recorder.waitForEvent { if case .signedOut = $0 { true } else { false } } != nil)

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(authorization: .required))
        }
        guard case .unauthenticated = error else {
            Issue.record("Ожидалась unauthenticated, получено \(String(describing: error))")
            return
        }
        #expect(server.requests.current.isEmpty)
    }

    @Test("Ошибка хранилища сообщается событием, но не ломает запрос")
    func storeFailureIsReported() async throws {
        let store = FailingCredentialStore()
        let refresher = CountingRefresher(result: .success(valid()))
        let server = MockServer { configuration in
            configuration.auth = .refreshable(store: store, refresher: refresher)
        }
        let recorder = AuthEventRecorder(server.client.auth)

        try await server.client.send(server.endpoint(authorization: .optional))

        #expect(await recorder.waitForEvent { if case .storeFailed = $0 { true } else { false } } != nil)
        #expect(server.requests.current.count == 1)
    }

    @Test("Запрос с .none не обновляет токен и не получает заголовок")
    func noneDoesNotRefresh() async throws {
        let store = InMemoryCredentialStore(expired())
        let refresher = CountingRefresher(result: .success(valid()))
        let server = MockServer(
            configure: { $0.auth = .refreshable(store: store, refresher: refresher) },
            handler: { request in try MockServer.respond(to: request) }
        )

        try await server.client.send(server.endpoint(authorization: .none))

        #expect(await refresher.count == 0)
        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

/// Обновление токена с подсчётом вызовов.
actor CountingRefresher: CredentialRefresher {
    typealias Credential = OAuth2Credential

    private(set) var count = 0
    private let result: Result<OAuth2Credential, any Error>
    private let delayNanoseconds: UInt64?

    init(result: Result<OAuth2Credential, any Error>, delayMilliseconds: UInt64? = nil) {
        self.result = result
        self.delayNanoseconds = delayMilliseconds.map { $0 * 1_000_000 }
    }

    func refresh(_ credential: OAuth2Credential) async throws -> OAuth2Credential {
        count += 1

        if let delayNanoseconds {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        return try result.get()
    }
}

/// Хранилище, которое всегда сообщает об ошибке.
private struct FailingCredentialStore: CredentialStore {
    struct StoreError: Error {}

    func load() async throws -> OAuth2Credential? {
        throw StoreError()
    }

    func save(_ credential: OAuth2Credential) async throws {
        throw StoreError()
    }

    func clear() async throws {
        throw StoreError()
    }
}
