import Foundation
import Gatewire
import Testing

@Suite("OAuth 2.0")
struct OAuth2Tests {
    // MARK: - Учётные данные

    @Test("requiresRefresh учитывает запас времени до истечения")
    func requiresRefreshUsesLeeway() {
        let expiringSoon = OAuth2Credential(
            accessToken: "a",
            expiresAt: Date().addingTimeInterval(30),
            refreshLeeway: 60
        )
        let valid = OAuth2Credential(
            accessToken: "a",
            expiresAt: Date().addingTimeInterval(600),
            refreshLeeway: 60
        )
        let withoutExpiration = OAuth2Credential(accessToken: "a")

        #expect(expiringSoon.requiresRefresh)
        #expect(valid.requiresRefresh == false)
        #expect(withoutExpiration.requiresRefresh == false)
    }

    @Test("Тип токена из ответа сервера нормализуется")
    func tokenTypeIsNormalized() throws {
        let credential = OAuth2Credential(OAuth2TokenResponse(accessToken: "abc", tokenType: "bearer"))

        #expect(credential.authorizationValue == "Bearer abc")

        var request = URLRequest(url: URL(string: "https://api.example.com")!)
        credential.apply(to: &request)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(credential.isApplied(to: request))
        #expect(OAuth2Credential(accessToken: "other").isApplied(to: request) == false)
    }

    @Test("expires_in превращается в момент истечения")
    func expiresInBecomesDate() {
        let issuedAt = Date(timeIntervalSince1970: 1_000_000)
        let credential = OAuth2Credential(
            OAuth2TokenResponse(accessToken: "abc", expiresIn: 3600),
            issuedAt: issuedAt
        )

        #expect(credential.expiresAt == issuedAt.addingTimeInterval(3600))
    }

    // MARK: - Обновление токена

    @Test("Запрос обновления отправляется по RFC 6749")
    func refreshRequestFormat() async throws {
        let (refresher, requests) = makeRefresher(
            json: #"{"access_token": "access-2", "token_type": "bearer", "expires_in": 3600}"#
        )

        let credential = try await refresher.refresh(
            OAuth2Credential(accessToken: "access-1", refreshToken: "refresh-1")
        )

        let request = try #require(requests.current.last)
        #expect(request.method == .post)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=refresh-1"))
        #expect(body.contains("client_id=ios-app"))
        #expect(credential.accessToken == "access-2")
        #expect(credential.expiresAt != nil)
    }

    @Test("Прежний refresh-токен сохраняется, если сервер не прислал новый")
    func previousRefreshTokenIsKept() async throws {
        let (refresher, _) = makeRefresher(json: #"{"access_token": "access-2"}"#)

        let credential = try await refresher.refresh(
            OAuth2Credential(accessToken: "access-1", refreshToken: "refresh-1")
        )

        #expect(credential.refreshToken == "refresh-1")
    }

    @Test("Новый refresh-токен заменяет прежний")
    func newRefreshTokenReplacesPrevious() async throws {
        let (refresher, _) = makeRefresher(
            json: #"{"access_token": "access-2", "refresh_token": "refresh-2"}"#
        )

        let credential = try await refresher.refresh(
            OAuth2Credential(accessToken: "access-1", refreshToken: "refresh-1")
        )

        #expect(credential.refreshToken == "refresh-2")
    }

    @Test("Секрет клиента можно передать заголовком Basic")
    func clientSecretInBasicHeader() async throws {
        let (refresher, requests) = makeRefresher(
            json: #"{"access_token": "access-2"}"#,
            clientSecret: "s3cret",
            clientAuthentication: .basicHeader
        )

        _ = try await refresher.refresh(
            OAuth2Credential(accessToken: "access-1", refreshToken: "refresh-1")
        )

        let request = try #require(requests.current.last)
        let expected = "Basic " + Data("ios-app:s3cret".utf8).base64EncodedString()
        #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("client_id") == false)
        #expect(body.contains("client_secret") == false)
    }

    @Test("Ошибка сервера разбирается по RFC 6749")
    func serverErrorIsParsed() async throws {
        let (refresher, _) = makeRefresher(
            status: 400,
            json: #"{"error": "invalid_grant", "error_description": "token expired"}"#
        )

        await #expect(throws: OAuth2Error.server(
            code: "invalid_grant",
            description: "token expired",
            statusCode: 400
        )) {
            try await refresher.refresh(OAuth2Credential(accessToken: "a", refreshToken: "refresh-1"))
        }
    }

    @Test("Неразбираемый ответ приходит как unexpectedResponse")
    func unexpectedResponse() async throws {
        let (refresher, _) = makeRefresher(status: 500, json: "<html>error</html>")

        await #expect(throws: OAuth2Error.unexpectedResponse(statusCode: 500)) {
            try await refresher.refresh(OAuth2Credential(accessToken: "a", refreshToken: "refresh-1"))
        }
    }

    @Test("Без refresh-токена обновление невозможно")
    func missingRefreshToken() async throws {
        let (refresher, requests) = makeRefresher(json: "{}")

        await #expect(throws: OAuth2Error.missingRefreshToken) {
            try await refresher.refresh(OAuth2Credential(accessToken: "a"))
        }
        #expect(requests.current.isEmpty)
    }

    @Test("Ошибка сети приходит как NetworkError.transport")
    func networkFailure() async throws {
        let requests = Locked<[URLRequest]>([])
        let (_, baseURL) = MockServer.registerHost { request in
            requests.withValue { $0.append(request) }
            throw URLError(.timedOut)
        }
        let refresher = OAuth2TokenRefresher(
            tokenURL: baseURL.appendingPathComponent("token"),
            clientID: "ios-app",
            sessionConfiguration: MockServer.sessionConfiguration
        )

        let error = await networkError { () async throws(NetworkError) in
            do {
                _ = try await refresher.refresh(
                    OAuth2Credential(accessToken: "a", refreshToken: "refresh-1")
                )
            } catch let error as NetworkError {
                throw error
            } catch {
                Issue.record("Ожидалась NetworkError, получено \(error)")
            }
        }

        guard case let .transport(urlError) = error else {
            Issue.record("Ожидалась transport, получено \(String(describing: error))")
            return
        }
        #expect(urlError.code == .timedOut)
    }

    // MARK: - Полный цикл

    @Test("Истёкший токен обновляется через token endpoint")
    func endToEndRefresh() async throws {
        let store = InMemoryCredentialStore(OAuth2Credential(
            accessToken: "old-access",
            refreshToken: "refresh-1",
            expiresAt: Date().addingTimeInterval(-10)
        ))
        let (_, tokenBaseURL) = MockServer.registerHost { request in
            try MockServer.respond(
                to: request,
                json: #"{"access_token": "fresh-access", "token_type": "Bearer", "expires_in": 3600}"#
            )
        }
        let refresher = OAuth2TokenRefresher(
            tokenURL: tokenBaseURL.appendingPathComponent("oauth/token"),
            clientID: "ios-app",
            sessionConfiguration: MockServer.sessionConfiguration
        )
        let server = MockServer { configuration in
            configuration.auth = .refreshable(store: store, refresher: refresher)
        }

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(server.lastRequest.current?.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access")
        #expect(try await store.load()?.accessToken == "fresh-access")
    }

    private func makeRefresher(
        status: Int = 200,
        json: String,
        clientSecret: String? = nil,
        clientAuthentication: OAuth2TokenRefresher.ClientAuthentication = .requestBody
    ) -> (OAuth2TokenRefresher, Locked<[URLRequest]>) {
        let requests = Locked<[URLRequest]>([])
        let (_, baseURL) = MockServer.registerHost { request in
            requests.withValue { $0.append(request) }
            return try MockServer.respond(to: request, status: status, json: json)
        }
        let refresher = OAuth2TokenRefresher(
            tokenURL: baseURL.appendingPathComponent("token"),
            clientID: "ios-app",
            clientSecret: clientSecret,
            clientAuthentication: clientAuthentication,
            sessionConfiguration: MockServer.sessionConfiguration
        )

        return (refresher, requests)
    }
}
