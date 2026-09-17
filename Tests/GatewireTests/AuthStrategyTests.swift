import Foundation
import Gatewire
import Testing

@Suite("Стратегии авторизации без обновления токена")
struct AuthStrategyTests {
    @Test("apiKey в заголовке")
    func apiKeyInHeader() async throws {
        let server = MockServer { $0.auth = .apiKey("secret-key") }

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "X-API-Key") == "secret-key")
    }

    @Test("apiKey в строке запроса не теряет параметры запроса")
    func apiKeyInQuery() async throws {
        let server = MockServer { $0.auth = .apiKey("secret-key", name: "api_key", in: .queryParameter) }

        try await server.client.send(server.endpoint(task: .query(["page": 2]), authorization: .required))

        let query = try #require(server.lastRequest.current?.url?.query)
        #expect(query.contains("page=2"))
        #expect(query.contains("api_key=secret-key"))
    }

    @Test("basic добавляет заголовок Authorization")
    func basicAuth() async throws {
        let server = MockServer { $0.auth = .basic(username: "user", password: "pa$$word") }

        try await server.client.send(server.endpoint(authorization: .required))

        let expected = "Basic " + Data("user:pa$$word".utf8).base64EncodedString()
        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test("custom использует переданный интерцептор")
    func customInterceptor() async throws {
        let server = MockServer { $0.auth = .custom(SigningInterceptor()) }

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "X-Signature") == "signed")
    }

    @Test("isAuthenticated отражает наличие токена у стратегии bearer")
    func bearerIsAuthenticated() async throws {
        let withToken = MockServer { $0.auth = .bearer { "token" } }
        let withoutToken = MockServer { $0.auth = .bearer { nil } }

        #expect(await withToken.client.auth.isAuthenticated())
        #expect(await withoutToken.client.auth.isAuthenticated() == false)
    }

    @Test("signIn для стратегии без хранилища сообщает об ошибке использования")
    func signInIsRejectedForStatelessStrategy() async throws {
        let server = MockServer { $0.auth = .bearer { "token" } }

        await #expect(throws: (any Error).self) {
            try await server.client.auth.signIn(with: OAuth2Credential(accessToken: "access"))
        }
    }

    @Test("signIn для ненастроенной схемы сообщает об ошибке использования")
    func signInIsRejectedForUnknownScheme() async throws {
        let server = MockServer()

        await #expect(throws: (any Error).self) {
            try await server.client.auth.signIn(with: OAuth2Credential(accessToken: "access"))
        }
        #expect(await server.client.auth.isAuthenticated() == false)
    }
}

private struct SigningInterceptor: RequestInterceptor {
    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        var request = urlRequest
        request.headers.update(name: "X-Signature", value: "signed")
        completion(.success(request))
    }
}
