import Foundation
import Gatewire
import Testing

@Suite("Авторизованная и неавторизованная зоны")
struct AuthorizationZoneTests {
    private func server(
        token: String? = "token-1",
        allowedHosts: Set<String>? = nil,
        configure: @escaping (inout APIConfiguration) -> Void = { _ in }
    ) -> MockServer {
        MockServer { configuration in
            configuration.auth = .bearer(allowedHosts: allowedHosts) { token }
            configure(&configuration)
        }
    }

    @Test("Запрос с .none не получает токен, хотя стратегия настроена")
    func noneNeverSendsToken() async throws {
        let server = server()

        try await server.client.send(server.endpoint(authorization: .none))

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Запрос с .required получает токен")
    func requiredSendsToken() async throws {
        let server = server()

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test("Без учётных данных .required не отправляет запрос")
    func requiredWithoutCredential() async throws {
        let server = server(token: nil)

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(authorization: .required))
        }

        guard case .unauthenticated = error else {
            Issue.record("Ожидалась unauthenticated, получено \(String(describing: error))")
            return
        }
        #expect(server.lastRequest.current == nil)
    }

    @Test("Запрос с .optional отправляется и без токена, и с токеном")
    func optionalWorksBothWays() async throws {
        let withoutToken = server(token: nil)
        try await withoutToken.client.send(withoutToken.endpoint(authorization: .optional))
        #expect(withoutToken.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == nil)

        let withToken = server()
        try await withToken.client.send(withToken.endpoint(authorization: .optional))
        #expect(withToken.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test("По умолчанию запросы требуют авторизации, если стратегия настроена")
    func inheritRequiresAuthWhenStrategyConfigured() async throws {
        let server = server(token: nil)

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint())
        }

        guard case .unauthenticated = error else {
            Issue.record("Ожидалась unauthenticated, получено \(String(describing: error))")
            return
        }
    }

    @Test("Без стратегий запросы выполняются без авторизации")
    func inheritWithoutStrategies() async throws {
        let server = MockServer()

        try await server.client.send(server.endpoint())

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("defaultAuthorization меняет поведение .inherit")
    func defaultAuthorizationOverride() async throws {
        let server = server { $0.defaultAuthorization = .none }

        try await server.client.send(server.endpoint())

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Ненастроенная схема: .required — ошибка, .optional — запрос без токена")
    func unknownScheme() async throws {
        let server = server()

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(authorization: .required("payments")))
        }

        guard case .invalidRequest = error else {
            Issue.record("Ожидалась invalidRequest, получено \(String(describing: error))")
            return
        }
        #expect(server.lastRequest.current == nil)

        try await server.client.send(server.endpoint(authorization: .optional("payments")))
        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Токен не уходит на хост вне allowedHosts")
    func allowedHostsBlockForeignHost() async throws {
        let server = server(allowedHosts: ["api.example.com"])

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(authorization: .required))
        }

        guard case .invalidRequest = error else {
            Issue.record("Ожидалась invalidRequest, получено \(String(describing: error))")
            return
        }
        #expect(server.lastRequest.current == nil)

        try await server.client.send(server.endpoint(authorization: .optional))
        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("allowedHosts принимает маску поддоменов")
    func allowedHostsMatching() async throws {
        let server = server(allowedHosts: ["*.gatewire.test"])

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test("Несколько схем: каждая применяет свои учётные данные")
    func multipleSchemes() async throws {
        let server = MockServer { configuration in
            configuration.auth = .bearer { "user-token" }
            configuration.additionalAuth = ["payments": .apiKey("payments-key", name: "X-Payments-Key")]
        }

        try await server.client.send(server.endpoint(authorization: .required))
        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer user-token")

        try await server.client.send(server.endpoint(authorization: .required("payments")))
        let paymentsRequest = try #require(server.lastRequest.current)
        #expect(paymentsRequest.value(forHTTPHeaderField: "X-Payments-Key") == "payments-key")
        #expect(paymentsRequest.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Скачивание в файл тоже проходит через авторизацию")
    func downloadUsesAuthorization() async throws {
        let server = server()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("gatewire-auth-\(UUID().uuidString)/file.txt")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        try await server.client.download(server.endpoint(authorization: .required), to: destination)

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }
}
