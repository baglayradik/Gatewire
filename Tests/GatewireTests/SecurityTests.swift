import Foundation
@testable import Gatewire
import Testing

@Suite("Перенаправления и проверка сертификатов")
struct SecurityTests {
    // MARK: - Перенаправления

    /// Создаёт клиент, у которого первый хост отвечает перенаправлением на второй.
    private func redirectingServers(
        statusCode: Int = 302,
        configure: @escaping (inout APIConfiguration) -> Void = { _ in }
    ) -> (client: APIClient, source: TestEndpoint, targetRequests: Locked<[URLRequest]>) {
        let targetRequests = Locked<[URLRequest]>([])
        let (_, targetBaseURL) = MockServer.registerHost { request in
            targetRequests.withValue { $0.append(request) }
            return try MockServer.respond(to: request, json: #"{"ok": true}"#)
        }
        let (_, sourceBaseURL) = MockServer.registerHost { request in
            try MockServer.respond(
                to: request,
                status: statusCode,
                json: "",
                headers: ["Location": targetBaseURL.appendingPathComponent("moved").absoluteString]
            )
        }

        let client = APIClient { configuration in
            configuration.sessionConfiguration = MockServer.sessionConfiguration
            configuration.auth = .bearer { "secret-token" }
            configure(&configuration)
        }

        return (client, TestEndpoint(baseURL: sourceBaseURL, authorization: .required), targetRequests)
    }

    @Test("По умолчанию при переходе на другой хост Authorization убирается")
    func stripsSensitiveHeadersOnCrossHostRedirect() async throws {
        let (client, endpoint, targetRequests) = redirectingServers()

        try await client.send(endpoint)

        let redirected = try #require(targetRequests.current.last)
        #expect(redirected.url?.path == "/v1/moved")
        #expect(redirected.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Режим follow сохраняет заголовки")
    func followKeepsHeaders() async throws {
        let (client, endpoint, targetRequests) = redirectingServers { $0.redirects = .follow }

        try await client.send(endpoint)

        let redirected = try #require(targetRequests.current.last)
        #expect(redirected.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test("Режим doNotFollow возвращает ответ 3xx как есть")
    func doNotFollowReturnsRedirectResponse() async throws {
        let (client, endpoint, targetRequests) = redirectingServers { $0.redirects = .doNotFollow }

        let error = await networkError { () async throws(NetworkError) in
            try await client.send(endpoint)
        }

        #expect(error?.statusCode == 302)
        #expect(targetRequests.current.isEmpty)
    }

    @Test("Перенаправление на тот же хост сохраняет заголовки")
    func sameHostRedirectKeepsHeaders() async throws {
        let requests = Locked<[URLRequest]>([])
        let host = Locked<String?>(nil)
        let (hostName, baseURL) = MockServer.registerHost { request in
            requests.withValue { $0.append(request) }

            if request.url?.path == "/v1/items" {
                let location = request.url?.deletingLastPathComponent()
                    .appendingPathComponent("moved").absoluteString ?? ""
                return try MockServer.respond(to: request, status: 302, json: "", headers: ["Location": location])
            }
            return try MockServer.respond(to: request)
        }
        host.withValue { $0 = hostName }

        let client = APIClient { configuration in
            configuration.sessionConfiguration = MockServer.sessionConfiguration
            configuration.auth = .bearer { "secret-token" }
        }

        try await client.send(TestEndpoint(baseURL: baseURL, authorization: .required))

        #expect(requests.current.count == 2)
        let redirected = try #require(requests.current.last)
        #expect(redirected.url?.path == "/v1/moved")
        #expect(redirected.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test("Своя маска заголовков для перенаправлений")
    func customStrippedHeaders() async throws {
        let (client, endpoint, targetRequests) = redirectingServers { configuration in
            configuration.redirects = .followStripping(["x-tenant"])
            configuration.defaultHeaders = ["X-Tenant": "acme"]
        }

        try await client.send(endpoint)

        let redirected = try #require(targetRequests.current.last)
        #expect(redirected.value(forHTTPHeaderField: "X-Tenant") == nil)
        // Authorization в этом режиме не входит в список, поэтому сохраняется.
        #expect(redirected.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    // MARK: - Проверка сертификатов

    @Test("Без настройки проверка сертификатов остаётся системной")
    func serverTrustIsSystemByDefault() {
        let client = APIClient()

        #expect(client.session.serverTrustManager == nil)
    }

    @Test("Закрепление сертификатов создаёт правило для указанного хоста")
    func pinnedCertificatesCreateEvaluator() throws {
        let client = APIClient {
            $0.serverTrust = .pinnedCertificates(["api.example.com": []])
        }

        let manager = try #require(client.session.serverTrustManager)
        #expect(try manager.serverTrustEvaluator(forHost: "api.example.com") != nil)
        // allHostsMustBeEvaluated по умолчанию true: для хоста без правила запрос не пройдёт.
        #expect(throws: (any Error).self) {
            try manager.serverTrustEvaluator(forHost: "other.example.com")
        }
    }

    @Test("Закрепление сертификатов из бандла")
    func pinnedCertificatesFromBundle() throws {
        let client = APIClient {
            $0.serverTrust = .pinnedCertificates(
                hosts: ["api.example.com"],
                in: Bundle(for: BundleToken.self),
                allHostsMustBeEvaluated: false
            )
        }

        let manager = try #require(client.session.serverTrustManager)
        #expect(try manager.serverTrustEvaluator(forHost: "api.example.com") != nil)
        #expect(try manager.serverTrustEvaluator(forHost: "other.example.com") == nil)
    }

    @Test("Свой ServerTrustManager передаётся в сессию")
    func customServerTrustManager() throws {
        let manager = ServerTrustManager(allHostsMustBeEvaluated: false, evaluators: [:])
        let client = APIClient { $0.serverTrust = .custom(manager) }

        #expect(client.session.serverTrustManager === manager)
    }
}

private final class BundleToken {}
