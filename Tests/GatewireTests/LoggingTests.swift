import Foundation
import Gatewire
import Testing

@Suite("Логирование и маскирование секретов")
struct LoggingTests {
    private func server(
        level: LoggingConfiguration.Level,
        maxBodyBytes: Int = 4096,
        responseJSON: String = #"{"ok": true}"#,
        configure: @escaping (inout APIConfiguration) -> Void = { _ in }
    ) -> (MockServer, Locked<[String]>) {
        let messages = Locked<[String]>([])
        let server = MockServer(
            configure: { configuration in
                var logging = LoggingConfiguration(level: level)
                logging.maxBodyBytes = maxBodyBytes
                logging.sink = { message in messages.withValue { $0.append(message) } }
                configuration.logging = logging
                configuration.auth = .bearer { "super-secret-token" }
                configure(&configuration)
            },
            handler: { request in
                try MockServer.respond(to: request, json: responseJSON)
            }
        )

        return (server, messages)
    }

    /// Ждёт, пока в лог попадут все ожидаемые строки: логгер пишет из очереди Alamofire.
    private func waitForMessages(_ messages: Locked<[String]>, count: Int) async -> [String] {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let current = messages.current
            if current.count >= count {
                return current
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return messages.current
    }

    @Test("Уровень disabled ничего не пишет")
    func disabledLevelWritesNothing() async throws {
        let (server, messages) = server(level: .disabled)

        try await server.client.send(server.endpoint(authorization: .required))

        #expect(await waitForMessages(messages, count: 1).isEmpty)
    }

    @Test("Уровень basic пишет метод, адрес и код ответа")
    func basicLevel() async throws {
        let (server, messages) = server(level: .basic)

        try await server.client.send(server.endpoint(path: "items", method: .post, authorization: .required))

        let log = await waitForMessages(messages, count: 2).joined(separator: "\n")
        #expect(log.contains("→ POST"))
        #expect(log.contains("/v1/items"))
        #expect(log.contains("← 200"))
        #expect(log.contains("Authorization") == false)
    }

    @Test("Уровень headers маскирует Authorization")
    func headersLevelRedactsAuthorization() async throws {
        let (server, messages) = server(level: .headers)

        try await server.client.send(server.endpoint(authorization: .required))

        let log = await waitForMessages(messages, count: 2).joined(separator: "\n")
        #expect(log.contains("Authorization: <скрыто>"))
        #expect(log.contains("super-secret-token") == false)
    }

    @Test("Уровень verbose маскирует секреты в телах запроса и ответа")
    func verboseLevelRedactsBodies() async throws {
        let (server, messages) = server(
            level: .verbose,
            responseJSON: #"{"access_token": "response-secret", "user": {"id": 1, "password": "p"}}"#
        )
        let body = ["login": "user", "password": "request-secret"]

        try await server.client.send(
            server.endpoint(method: .post, task: .json(body), authorization: .required)
        )

        let log = await waitForMessages(messages, count: 2).joined(separator: "\n")
        #expect(log.contains("request-secret") == false)
        #expect(log.contains("response-secret") == false)
        #expect(log.contains("\"password\":\"<скрыто>\""))
        #expect(log.contains("\"access_token\":\"<скрыто>\""))
        #expect(log.contains("\"login\":\"user\""))
    }

    @Test("Секреты в строке запроса маскируются")
    func redactsQueryParameters() async throws {
        let (server, messages) = server(level: .basic)

        try await server.client.send(
            server.endpoint(task: .query(["token": "query-secret", "page": "2"]), authorization: .none)
        )

        let log = await waitForMessages(messages, count: 2).joined(separator: "\n")
        #expect(log.contains("query-secret") == false)
        #expect(log.contains("token=%3C%D1%81%D0%BA%D1%80%D1%8B%D1%82%D0%BE%3E") || log.contains("token=<скрыто>"))
        #expect(log.contains("page=2"))
    }

    @Test("Секреты в form-теле маскируются")
    func redactsFormBody() async throws {
        let (server, messages) = server(level: .verbose)

        try await server.client.send(
            server.endpoint(
                method: .post,
                task: .form(["grant_type": "password", "password": "form-secret"]),
                authorization: .none
            )
        )

        let log = await waitForMessages(messages, count: 2).joined(separator: "\n")
        #expect(log.contains("form-secret") == false)
        #expect(log.contains("password=<скрыто>"))
        #expect(log.contains("grant_type=password"))
    }

    @Test("Большое тело обрезается")
    func truncatesLargeBody() async throws {
        let longValue = String(repeating: "a", count: 500)
        let (server, messages) = server(
            level: .verbose,
            maxBodyBytes: 100,
            responseJSON: #"{"value": "\#(longValue)"}"#
        )

        try await server.client.send(server.endpoint(authorization: .none))

        let log = await waitForMessages(messages, count: 2).joined(separator: "\n")
        #expect(log.contains("обрезано"))
        #expect(log.contains(longValue) == false)
    }

    @Test("Ошибка запроса тоже попадает в лог")
    func logsFailures() async throws {
        let messages = Locked<[String]>([])
        let server = MockServer(
            configure: { configuration in
                var logging = LoggingConfiguration(level: .basic)
                logging.sink = { message in messages.withValue { $0.append(message) } }
                configuration.logging = logging
                // Без этого ошибка сети была бы повторена, и тест ждал бы задержки между повторами.
                configuration.retry = .disabled
            },
            handler: { _ in throw URLError(.notConnectedToInternet) }
        )

        _ = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint())
        }

        let log = await waitForMessages(messages, count: 2).joined(separator: "\n")
        #expect(log.contains("✗"))
    }
}
