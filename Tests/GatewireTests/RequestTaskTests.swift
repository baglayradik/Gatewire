import Foundation
import Gatewire
import Testing

@Suite("RequestTask: параметры и тело запроса")
struct RequestTaskTests {
    private let baseURL = URL(string: "https://api.example.com")!

    private func request(_ task: RequestTask, method: HTTPMethod = .post, headers: HTTPHeaders = [:]) throws -> URLRequest {
        try TestEndpoint(baseURL: baseURL, method: method, task: task, headers: headers).asURLRequest()
    }

    @Test("plain не добавляет тело и параметры")
    func plain() throws {
        let request = try request(.plain)
        #expect(request.httpBody == nil)
        #expect(request.url?.query == nil)
    }

    @Test("query кодирует параметры в строку запроса даже для POST")
    func query() throws {
        let request = try request(.query(["q": "swift concurrency", "page": "2"]))

        #expect(request.url?.query == "page=2&q=swift%20concurrency")
        #expect(request.httpBody == nil)
    }

    @Test("json кодирует тело и выставляет Content-Type")
    func json() throws {
        let request = try request(.json(UserDTO(id: 7, fullName: "Test User")))

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        #expect(try JSONDecoder().decode(UserDTO.self, from: body) == UserDTO(id: 7, fullName: "Test User"))
    }

    @Test("json использует jsonEncoder эндпоинта")
    func jsonUsesEndpointEncoder() throws {
        var endpoint = TestEndpoint(baseURL: baseURL, method: .post, task: .json(UserDTO(id: 7, fullName: "Test User")))
        endpoint.jsonEncoder = .snakeCaseISO8601

        let body = try #require(try endpoint.asURLRequest().httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["full_name"] as? String == "Test User")
    }

    @Test("form кодирует тело x-www-form-urlencoded")
    func form() throws {
        let request = try request(.form(["login": "user", "password": "p@ss word"]))

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8")
        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == "login=user&password=p%40ss%20word")
    }

    @Test("queryAndJSON кодирует и строку запроса, и тело")
    func queryAndJSON() throws {
        let request = try request(.queryAndJSON(query: ["dry_run": "true"], body: UserDTO(id: 1, fullName: "A")))

        #expect(request.url?.query == "dry_run=true")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody != nil)
    }

    @Test("raw передаёт тело и Content-Type как есть")
    func raw() throws {
        let xml = Data("<user id=\"1\"/>".utf8)
        let request = try request(.raw(xml, contentType: "application/xml"))

        #expect(request.httpBody == xml)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/xml")
    }

    @Test("Content-Type из заголовков эндпоинта не перезаписывается")
    func explicitContentTypeWins() throws {
        let headers: HTTPHeaders = ["Content-Type": "application/vnd.api+json"]

        let raw = try request(.raw(Data(), contentType: "application/xml"), headers: headers)
        #expect(raw.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")

        let json = try request(.json(["a": 1]), headers: headers)
        #expect(json.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
    }

    @Test("Ошибка кодирования приходит как NetworkError.encodingFailed")
    func encodingFailure() throws {
        #expect {
            try request(.json(FailingEncodable()))
        } throws: { error in
            guard case .encodingFailed = error as? NetworkError else { return false }
            return true
        }
    }
}

private struct FailingEncodable: Encodable, Sendable {
    func encode(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "Тестовая ошибка кодирования"))
    }
}
