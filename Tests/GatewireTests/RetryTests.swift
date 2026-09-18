import Foundation
import Gatewire
import Testing

@Suite("Повторы запросов")
struct RetryTests {
    /// Отвечает заданными кодами по очереди; когда коды заканчиваются — 200.
    private func server(
        statusCodes: [Int],
        configure: @escaping (inout APIConfiguration) -> Void = { _ in }
    ) -> MockServer {
        let remaining = Locked(statusCodes)

        return MockServer(
            configure: { configuration in
                // Ускоряем задержки между повторами, чтобы тест не ждал секунды.
                configuration.retry.exponentialBackoffScale = 0.001
                configure(&configuration)
            },
            handler: { request in
                let status = remaining.withValue { codes in
                    codes.isEmpty ? 200 : codes.removeFirst()
                }
                return try MockServer.respond(to: request, status: status, json: #"{"ok": true}"#)
            }
        )
    }

    @Test("Ответ 503 повторяется, пока запрос не пройдёт")
    func retriesServerErrors() async throws {
        let server = server(statusCodes: [503, 503])

        try await server.client.send(server.endpoint())

        #expect(server.requests.current.count == 3)
    }

    @Test("Повторов не больше, чем задано лимитом")
    func respectsLimit() async throws {
        let server = server(statusCodes: [503, 503, 503, 503]) { $0.retry.limit = 1 }

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint())
        }

        #expect(error?.statusCode == 503)
        #expect(server.requests.current.count == 2)
    }

    @Test("POST по умолчанию не повторяется")
    func doesNotRetryPostByDefault() async throws {
        let server = server(statusCodes: [503])

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(method: .post))
        }

        #expect(error?.statusCode == 503)
        #expect(server.requests.current.count == 1)
    }

    @Test("POST повторяется, если он добавлен в настройки")
    func retriesPostWhenConfigured() async throws {
        let server = server(statusCodes: [503]) { $0.retry.methods.insert(.post) }

        try await server.client.send(server.endpoint(method: .post))

        #expect(server.requests.current.count == 2)
    }

    @Test("Повторы можно отключить")
    func retriesCanBeDisabled() async throws {
        let server = server(statusCodes: [503]) { $0.retry = .disabled }

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint())
        }

        #expect(error?.statusCode == 503)
        #expect(server.requests.current.count == 1)
    }

    @Test("Код ответа вне списка не повторяется")
    func doesNotRetryUnlistedStatusCode() async throws {
        let server = server(statusCodes: [404])

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint())
        }

        #expect(error?.statusCode == 404)
        #expect(server.requests.current.count == 1)
    }

    @Test("Ответ 401 повторами не обрабатывается")
    func doesNotRetryUnauthorized() async throws {
        let server = server(statusCodes: [401, 401, 401])

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(authorization: .none))
        }

        #expect(error?.statusCode == 401)
        #expect(server.requests.current.count == 1)
    }

    @Test("Обрыв соединения повторяется")
    func retriesNetworkFailures() async throws {
        let attempts = Locked(0)
        let server = MockServer(
            configure: { $0.retry.exponentialBackoffScale = 0.001 },
            handler: { request in
                let attempt = attempts.withValue { count -> Int in
                    count += 1
                    return count
                }
                guard attempt > 2 else { throw URLError(.networkConnectionLost) }

                return try MockServer.respond(to: request)
            }
        )

        try await server.client.send(server.endpoint())

        #expect(attempts.current == 3)
    }

    @Test("Ошибка кодирования не повторяется")
    func doesNotRetryEncodingFailures() async throws {
        let server = MockServer()

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(method: .post, task: .json(BrokenEncodable())))
        }

        guard case .encodingFailed = error else {
            Issue.record("Ожидалась encodingFailed, получено \(String(describing: error))")
            return
        }
        #expect(server.requests.current.isEmpty)
    }
}

private struct BrokenEncodable: Encodable, Sendable {
    func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "Тестовая ошибка"))
    }
}
