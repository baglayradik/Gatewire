import Foundation
import Gatewire
import Testing

@Suite("ResponseDecoder: форматы ответов")
struct ResponseDecoderTests {
    // MARK: - EnvelopeDecoder

    @Test("envelope извлекает полезные данные из обёртки")
    func envelopeUnwrapsPayload() async throws {
        let server = MockServer { request in
            try MockServer.respond(
                to: request,
                json: #"{"success": true, "data": {"id": 3, "fullName": "Wrapped"}}"#
            )
        }

        let user = try await server.client.request(
            server.endpoint(),
            decoder: .envelope(TestEnvelope<UserDTO>.self)
        )

        #expect(user == UserDTO(id: 3, fullName: "Wrapped"))
    }

    @Test("Ошибка внутри успешного ответа приходит как NetworkError.api")
    func envelopeErrorBecomesAPIError() async throws {
        let body = #"{"success": false, "error": {"code": "session_expired"}}"#
        let server = MockServer { request in
            try MockServer.respond(to: request, json: body)
        }

        let error = await networkError { () async throws(NetworkError) in
            _ = try await server.client.request(
                server.endpoint(),
                decoder: .envelope(TestEnvelope<UserDTO>.self)
            )
        }

        guard case let .api(apiError as EnvelopeError, response, data) = error else {
            Issue.record("Ожидалась api, получено \(String(describing: error))")
            return
        }
        #expect(apiError.code == "session_expired")
        #expect(response.statusCode == 200)
        #expect(data == Data(body.utf8))
    }

    @Test("Некорректная обёртка приходит как decodingFailed")
    func malformedEnvelope() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: #"{"unexpected": 1}"#)
        }

        let error = await networkError { () async throws(NetworkError) in
            _ = try await server.client.request(
                server.endpoint(),
                decoder: .envelope(TestEnvelope<UserDTO>.self)
            )
        }

        guard case .decodingFailed = error else {
            Issue.record("Ожидалась decodingFailed, получено \(String(describing: error))")
            return
        }
    }

    // MARK: - NestedResponseDecoder

    @Test("nested декодирует значение по пути из ключей", arguments: [
        ("data", #"{"data": {"id": 1, "fullName": "One"}}"#),
        ("data.user", #"{"data": {"user": {"id": 1, "fullName": "One"}}, "meta": {}}"#),
        ("result.payload.user", #"{"result": {"payload": {"user": {"id": 1, "fullName": "One"}}}}"#),
    ])
    func nestedKeyPath(keyPath: String, json: String) async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: json)
        }

        let user = try await server.client.request(
            server.endpoint(),
            decoder: .nested(UserDTO.self, at: keyPath)
        )

        #expect(user == UserDTO(id: 1, fullName: "One"))
    }

    @Test("nested использует декодер клиента со стратегией ключей")
    func nestedUsesClientDecoder() async throws {
        let server = MockServer(configure: { $0.decoder = JSONDecoder.snakeCaseISO8601 }) { request in
            try MockServer.respond(
                to: request,
                json: #"{"response_data": [{"id": 1, "full_name": "Snake"}]}"#
            )
        }

        let users = try await server.client.request(
            server.endpoint(),
            decoder: .nested([UserDTO].self, at: "responseData")
        )

        #expect(users == [UserDTO(id: 1, fullName: "Snake")])
    }

    @Test("Отсутствующий ключ пути приходит как decodingFailed")
    func nestedMissingKey() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: #"{"data": {}}"#)
        }

        let error = await networkError { () async throws(NetworkError) in
            _ = try await server.client.request(
                server.endpoint(),
                decoder: .nested(UserDTO.self, at: "data.user")
            )
        }

        guard case let .decodingFailed(underlying, _) = error else {
            Issue.record("Ожидалась decodingFailed, получено \(String(describing: error))")
            return
        }
        #expect(underlying is DecodingError)
    }

    @Test("Параллельные nested-декодеры с разными путями не мешают друг другу")
    func concurrentNestedDecoders() async throws {
        let server = MockServer { request in
            try MockServer.respond(
                to: request,
                json: #"{"a": {"id": 1, "fullName": "A"}, "b": {"id": 2, "fullName": "B"}}"#
            )
        }

        let ids = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<40 {
                let key = index.isMultiple(of: 2) ? "a" : "b"
                group.addTask {
                    try await server.client.request(server.endpoint(), decoder: .nested(UserDTO.self, at: key)).id
                }
            }
            return try await group.reduce(into: [Int]()) { $0.append($1) }
        }

        #expect(ids.filter { $0 == 1 }.count == 20)
        #expect(ids.filter { $0 == 2 }.count == 20)
    }

    // MARK: - Свой декодер

    @Test("Свой декодер получает HTTP-ответ и декодер эндпоинта")
    func customDecoderReceivesContext() async throws {
        let server = MockServer { request in
            try MockServer.respond(
                to: request,
                json: #"{"id": 1, "full_name": "Context"}"#,
                headers: ["Content-Type": "application/json", "X-Total-Count": "57"]
            )
        }
        var endpoint = server.endpoint()
        endpoint.decoder = JSONDecoder.snakeCaseISO8601

        let (user, total) = try await server.client.request(endpoint, decoder: CountedDecoder())

        #expect(user.fullName == "Context")
        #expect(total == 57)
    }

    @Test("NetworkError из своего декодера передаётся без изменений")
    func networkErrorFromDecoderPassesThrough() async throws {
        let server = MockServer()

        let error = await networkError { () async throws(NetworkError) in
            _ = try await server.client.request(server.endpoint(), decoder: CancellingDecoder())
        }

        guard case .cancelled = error else {
            Issue.record("Ожидалась cancelled, получено \(String(describing: error))")
            return
        }
    }
}

private struct EnvelopeError: Decodable, Error {
    let code: String
}

private struct TestEnvelope<Payload: Decodable & Sendable>: ResponseEnvelope {
    let success: Bool
    let data: Payload?
    let error: EnvelopeError?

    func unwrap() throws -> Payload {
        guard success, let data else {
            throw error ?? EnvelopeError(code: "unknown")
        }
        return data
    }
}

private struct CountedDecoder: ResponseDecoder {
    func decode(_ data: Data, context: ResponseDecodingContext) throws -> (UserDTO, Int?) {
        let user = try context.dataDecoder.decode(UserDTO.self, from: data)
        let total = context.response.value(forHTTPHeaderField: "X-Total-Count").flatMap(Int.init)
        return (user, total)
    }
}

private struct CancellingDecoder: ResponseDecoder {
    func decode(_ data: Data, context: ResponseDecodingContext) throws -> Data {
        throw NetworkError.cancelled
    }
}
