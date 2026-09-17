import Foundation
import Gatewire
import Testing

@Suite("APIClient: загрузка и скачивание")
struct TransferTests {
    // MARK: - Загрузка

    // URLProtocol не сообщает URLSession об отправленных байтах, поэтому вызовы обработчика
    // прогресса отправки в этих тестах не проверяются — только отправка тела и разбор ответа.
    // Прогресс отправки проверяется на реальной сети.

    @Test("upload(_:as:progress:) отправляет тело и декодирует ответ")
    func uploadDecodesResponse() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, status: 201, json: #"{"id": 9, "fullName": "Uploaded"}"#)
        }
        let endpoint = server.endpoint(path: "avatar", method: .post, task: .multipart { formData in
            formData.append(Data("avatar-bytes".utf8), withName: "avatar", fileName: "a.jpg", mimeType: "image/jpeg")
        })

        let user = try await server.client.upload(endpoint, as: UserDTO.self) { _ in }

        #expect(user == UserDTO(id: 9, fullName: "Uploaded"))
        let body = String(decoding: try #require(server.lastRequest.current?.httpBody), as: UTF8.self)
        #expect(body.contains("avatar-bytes"))
    }

    @Test("upload(_:progress:) без разбора ответа и с декодером")
    func uploadWithoutBodyAndWithDecoder() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: "stored", headers: ["Content-Type": "text/plain"])
        }
        let endpoint = server.endpoint(method: .put, task: .raw(Data("file".utf8), contentType: "text/plain"))

        try await server.client.upload(endpoint) { _ in }
        let text = try await server.client.upload(endpoint, decoder: .string) { _ in }

        #expect(text == "stored")
        #expect(server.lastRequest.current?.httpBody == Data("file".utf8))
    }

    // MARK: - Скачивание

    @Test("download сохраняет ответ в файл и сообщает прогресс")
    func downloadSavesFile() async throws {
        let payload = Data(repeating: 0xAB, count: 64_000)
        let server = MockServer { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(payload.count)", "Content-Type": "application/octet-stream"]
            ))
            return (response, payload)
        }
        let destination = temporaryDirectory().appendingPathComponent("nested/dir/file.bin")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        let updates = Locked<[TransferProgress]>([])

        let fileURL = try await server.client.download(server.endpoint(path: "file"), to: destination) { progress in
            updates.withValue { $0.append(progress) }
        }

        #expect(fileURL == destination)
        #expect(try Data(contentsOf: destination) == payload)

        // О записанных байтах URLSession сообщает только на macOS: на симуляторе iOS
        // подменённый через URLProtocol ответ не порождает вызовов обработчика прогресса.
        #if os(macOS)
        let lastUpdate = try #require(updates.current.last)
        #expect(lastUpdate.completedBytes == Int64(payload.count))
        #expect(lastUpdate.fractionCompleted == 1)
        #endif
    }

    @Test("download заменяет существующий файл")
    func downloadReplacesExistingFile() async throws {
        let server = MockServer { request in
            try MockServer.respond(to: request, json: "new content", headers: ["Content-Type": "text/plain"])
        }
        let destination = temporaryDirectory().appendingPathComponent("file.txt")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("old content".utf8).write(to: destination)

        try await server.client.download(server.endpoint(), to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "new content")
    }

    @Test("При недопустимом коде ответа файл удаляется, а тело приходит в ошибке")
    func downloadErrorRemovesFile() async throws {
        let server = MockServer(configure: { $0.errorMapper = MessageErrorMapper() }) { request in
            try MockServer.respond(to: request, status: 404, json: #"{"message": "no such report"}"#)
        }
        let destination = temporaryDirectory().appendingPathComponent("report.pdf")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.download(server.endpoint(), to: destination)
        }

        guard case let .api(apiError as MessageError, response, _) = error else {
            Issue.record("Ожидалась api, получено \(String(describing: error))")
            return
        }
        #expect(apiError.message == "no such report")
        #expect(response.statusCode == 404)
        #expect(FileManager.default.fileExists(atPath: destination.path) == false)
    }

    @Test("download не поддерживает multipart")
    func downloadRejectsMultipart() async throws {
        let server = MockServer()
        let endpoint = server.endpoint(method: .post, task: .multipart { _ in })

        let error = await networkError { () async throws(NetworkError) in
            try await server.client.download(endpoint, to: temporaryDirectory().appendingPathComponent("x"))
        }

        guard case .invalidRequest = error else {
            Issue.record("Ожидалась invalidRequest, получено \(String(describing: error))")
            return
        }
        #expect(server.lastRequest.current == nil)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gatewire-tests-\(UUID().uuidString)")
    }
}

private struct MessageError: Decodable, Error {
    let message: String
}

private struct MessageErrorMapper: APIErrorMapper {
    func map(response: HTTPURLResponse, data: Data) -> (any Error)? {
        try? JSONDecoder().decode(MessageError.self, from: data)
    }
}
