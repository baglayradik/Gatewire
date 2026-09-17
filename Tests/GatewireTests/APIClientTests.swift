import Foundation
@testable import Gatewire
import Testing

@Suite("APIClient: выполнение запросов")
struct APIClientTests {
    // MARK: - Успешные ответы

    @Test("request(_:as:) декодирует Decodable-ответ")
    func decodesResponse() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: #"{"id": 1, "fullName": "Test User"}"#)
        }

        let user = try await server.client.request(server.endpoint(), as: UserDTO.self)

        #expect(user == UserDTO(id: 1, fullName: "Test User"))
        #expect(server.lastRequest.current?.url?.path == "/v1/items")
    }

    @Test("Тип ответа выводится из контекста")
    func infersResponseType() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: #"[{"id": 1, "fullName": "A"}, {"id": 2, "fullName": "B"}]"#)
        }

        let users: [UserDTO] = try await server.client.request(server.endpoint())

        #expect(users.map(\.id) == [1, 2])
    }

    @Test("decoder эндпоинта важнее decoder из конфигурации")
    func endpointDecoderOverridesConfiguration() async throws {
        let server = MockServer(configure: { $0.decoder = JSONDecoder() }) { request in
            try MockServer.respond(to: request, json: #"{"id": 1, "full_name": "Snake Case"}"#)
        }
        var endpoint = server.endpoint()
        endpoint.decoder = JSONDecoder.snakeCaseISO8601

        let user = try await server.client.request(endpoint, as: UserDTO.self)

        #expect(user.fullName == "Snake Case")
    }

    @Test("decoder из конфигурации используется, если у эндпоинта его нет")
    func configurationDecoder() async throws {
        let server = MockServer(configure: { $0.decoder = JSONDecoder.snakeCaseISO8601 }) { request in
            try MockServer.respond(to: request, json: #"{"id": 1, "full_name": "Snake Case"}"#)
        }

        let user = try await server.client.request(server.endpoint(), as: UserDTO.self)

        #expect(user.fullName == "Snake Case")
    }

    @Test("request(_:decoder:) использует переданный ResponseDecoder")
    func customResponseDecoder() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: "plain text", headers: ["Content-Type": "text/plain; charset=utf-8"])
        }

        let text = try await server.client.request(server.endpoint(), decoder: .string)

        #expect(text == "plain text")
    }

    @Test("send(_:) принимает ответ без тела", arguments: [200, 204])
    func sendAcceptsEmptyBody(status: Int) async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, status: status, json: "")
        }

        try await server.client.send(server.endpoint(method: .delete))

        #expect(server.lastRequest.current?.method == .delete)
    }

    @Test("data(_:) возвращает тело без декодирования")
    func rawData() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: "raw bytes")
        }

        let data = try await server.client.data(server.endpoint())

        #expect(data == Data("raw bytes".utf8))
    }

    @Test("response(_:as:) возвращает код и заголовки ответа")
    func responseMetadata() async throws {
        let server = MockServer { request in
            try MockServer.respond(
                to: request,
                status: 201,
                json: #"{"id": 5, "fullName": "Created"}"#,
                headers: ["Content-Type": "application/json", "Location": "/v1/items/5"]
            )
        }

        let response = try await server.client.response(server.endpoint(method: .post), as: UserDTO.self)

        #expect(response.value.id == 5)
        #expect(response.statusCode == 201)
        #expect(response.headers["Location"] == "/v1/items/5")
    }

    @Test("Своя допустимая область кодов ответа")
    func customAcceptableStatusCodes() async throws {
        let server = MockServer(configure: { $0.acceptableStatusCodes = 200..<500 }) { request in
            try MockServer.respond(to: request, status: 404)
        }

        try await server.client.send(server.endpoint())
    }

    @Test("multipart отправляется как multipart/form-data")
    func multipart() async throws {
        let server = MockServer()
        let endpoint = server.endpoint(path: "avatar", method: .post, task: .multipart { formData in
            formData.append(Data("image-bytes".utf8), withName: "avatar", fileName: "avatar.jpg", mimeType: "image/jpeg")
        })

        try await server.client.send(endpoint)

        let request = try #require(server.lastRequest.current)
        #expect(request.method == .post)
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains(#"name="avatar"; filename="avatar.jpg""#))
        #expect(body.contains("image-bytes"))
    }

    // MARK: - Заголовки и таймаут

    @Test("Заголовки по умолчанию добавляются, заголовки эндпоинта важнее")
    func defaultHeaders() async throws {
        let server = MockServer(configure: {
            $0.defaultHeaders = ["Accept": "application/json", "X-Client": "gatewire"]
        })

        try await server.client.send(server.endpoint(headers: ["Accept": "text/plain"]))

        let request = try #require(server.lastRequest.current)
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/plain")
        #expect(request.value(forHTTPHeaderField: "X-Client") == "gatewire")
    }

    @Test("Таймаут берётся из эндпоинта, иначе из конфигурации")
    func timeout() throws {
        let client = APIClient { $0.timeout = 12 }
        var endpoint = TestEndpoint(baseURL: URL(string: "https://api.example.com")!)

        #expect(try client.makeURLRequest(for: endpoint).timeoutInterval == 12)

        endpoint.timeoutInterval = 3
        #expect(try client.makeURLRequest(for: endpoint).timeoutInterval == 3)
    }

    // MARK: - Ошибки

    @Test("Недопустимый код ответа приходит с телом и HTTP-ответом")
    func unacceptableStatusCode() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, status: 404, json: #"{"message": "not found"}"#)
        }

        let error = await networkError { () async throws(NetworkError) in
            _ = try await server.client.request(server.endpoint(), as: UserDTO.self)
        }

        guard case let .unacceptableStatusCode(response, data) = error else {
            Issue.record("Ожидалась unacceptableStatusCode, получено \(String(describing: error))")
            return
        }
        #expect(response.statusCode == 404)
        #expect(data == Data(#"{"message": "not found"}"#.utf8))
        #expect(error?.statusCode == 404)
    }

    @Test("errorMapper превращает тело ошибки в доменную ошибку")
    func errorMapper() async throws {
        let server = MockServer(configure: { $0.errorMapper = TestErrorMapper() }) { request in
            try MockServer.respond(to: request, status: 422, json: #"{"code": "invalid_email"}"#)
        }

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(method: .post))
        }

        guard case let .api(apiError as TestServerError, response, _) = error else {
            Issue.record("Ожидалась api, получено \(String(describing: error))")
            return
        }
        #expect(apiError.code == "invalid_email")
        #expect(response.statusCode == 422)
    }

    @Test("Если errorMapper не распознал тело, приходит unacceptableStatusCode")
    func errorMapperFallback() async throws {
        let server = MockServer(configure: { $0.errorMapper = TestErrorMapper() }) { request in
            try MockServer.respond(to: request, status: 500, json: "<html>Internal Server Error</html>")
        }

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint())
        }

        guard case .unacceptableStatusCode = error else {
            Issue.record("Ожидалась unacceptableStatusCode, получено \(String(describing: error))")
            return
        }
    }

    @Test("Ошибка декодирования содержит исходное тело")
    func decodingFailure() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: #"{"unexpected": true}"#)
        }

        let error = await networkError { () async throws(NetworkError) in
            _ = try await server.client.request(server.endpoint(), as: UserDTO.self)
        }

        guard case let .decodingFailed(underlying, data) = error else {
            Issue.record("Ожидалась decodingFailed, получено \(String(describing: error))")
            return
        }
        #expect(underlying is DecodingError)
        #expect(data == Data(#"{"unexpected": true}"#.utf8))
    }

    @Test("Ошибка сети приходит как transport с исходным URLError")
    func transportFailure() async throws {
        let server = MockServer { _ in
            throw URLError(.notConnectedToInternet)
        }

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint())
        }

        guard case let .transport(urlError) = error else {
            Issue.record("Ожидалась transport, получено \(String(describing: error))")
            return
        }
        #expect(urlError.code == .notConnectedToInternet)
    }

    @Test("Ошибка кодирования приходит до отправки запроса")
    func encodingFailureIsNotSent() async throws {
        let server = MockServer()
        let endpoint = server.endpoint(method: .post, task: .json(FailingEncodable()))

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(endpoint)
        }

        guard case .encodingFailed = error else {
            Issue.record("Ожидалась encodingFailed, получено \(String(describing: error))")
            return
        }
        #expect(server.lastRequest.current == nil)
    }

    @Test("Тело в GET-запросе — invalidRequest")
    func bodyInGETRequest() async throws {
        let server = MockServer()

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.send(server.endpoint(method: .get, task: .raw(Data("body".utf8), contentType: "text/plain")))
        }

        guard case .invalidRequest = error else {
            Issue.record("Ожидалась invalidRequest, получено \(String(describing: error))")
            return
        }
        #expect(server.lastRequest.current == nil)
    }

    // MARK: - Отмена

    @Test("Отмена задачи отменяет запрос")
    func cancellation() async throws {
        let started = AsyncStream<Void>.makeStream()
        let server = MockServer { request in
            started.continuation.yield()
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return try MockServer.respond(to: request)
        }

        let task = Task { () async -> NetworkError? in
            await networkError { () async throws(NetworkError) in
                try await server.client.send(server.endpoint())
            }
        }
        for await _ in started.stream { break }
        task.cancel()

        let error = await task.value
        guard case .cancelled = error else {
            Issue.record("Ожидалась cancelled, получено \(String(describing: error))")
            return
        }
    }

    @Test("Запрос из уже отменённой задачи не отправляется")
    func alreadyCancelledTask() async throws {
        let server = MockServer()

        let task = Task { () async -> NetworkError? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await networkError { () async throws(NetworkError) in
                try await server.client.send(server.endpoint())
            }
        }

        let error = await task.value
        guard case .cancelled = error else {
            Issue.record("Ожидалась cancelled, получено \(String(describing: error))")
            return
        }
        #expect(server.lastRequest.current == nil)
    }
}

private struct TestServerError: Decodable, Error {
    let code: String
}

private struct TestErrorMapper: APIErrorMapper {
    func map(response: HTTPURLResponse, data: Data) -> (any Error)? {
        try? JSONDecoder().decode(TestServerError.self, from: data)
    }
}

private struct FailingEncodable: Encodable, Sendable {
    func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "Тестовая ошибка кодирования"))
    }
}
