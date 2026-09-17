import Foundation
import Gatewire
import Testing

@Suite("Endpoint: сборка URLRequest")
struct EndpointTests {
    private let baseURL = URL(string: "https://api.example.com/v1")!

    @Test("Путь добавляется к baseURL", arguments: [
        ("items", "https://api.example.com/v1/items"),
        ("/items", "https://api.example.com/v1/items"),
        ("users/42/posts", "https://api.example.com/v1/users/42/posts"),
        ("", "https://api.example.com/v1"),
    ])
    func pathIsAppendedToBaseURL(path: String, expectedURL: String) throws {
        let request = try TestEndpoint(baseURL: baseURL, path: path).asURLRequest()
        #expect(request.url?.absoluteString == expectedURL)
    }

    @Test("Завершающий слеш в baseURL не дублируется")
    func trailingSlashInBaseURL() throws {
        let endpoint = TestEndpoint(baseURL: URL(string: "https://api.example.com/v1/")!, path: "/items")
        #expect(try endpoint.asURLRequest().url?.absoluteString == "https://api.example.com/v1/items")
    }

    @Test("Метод, заголовки и таймаут переносятся в запрос")
    func methodHeadersAndTimeout() throws {
        var endpoint = TestEndpoint(baseURL: baseURL, method: .delete, headers: ["X-Request-ID": "42"])
        endpoint.timeoutInterval = 5

        let request = try endpoint.asURLRequest()

        #expect(request.method == .delete)
        #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "42")
        #expect(request.timeoutInterval == 5)
    }

    @Test("Значения по умолчанию: GET без тела")
    func defaults() throws {
        let request = try MinimalRouter.ping.asURLRequest()

        #expect(request.method == .get)
        #expect(request.httpBody == nil)
        #expect(request.url?.absoluteString == "https://api.example.com/ping")
    }

    @Test("Роутер описывает несколько запросов")
    func routerBuildsDifferentRequests() throws {
        let profile = try UserRouter.profile.asURLRequest()
        #expect(profile.method == .get)
        #expect(profile.url?.absoluteString == "https://api.example.com/v1/me")

        let posts = try UserRouter.posts(userID: 42, page: 2).asURLRequest()
        #expect(posts.url?.absoluteString == "https://api.example.com/v1/users/42/posts?page=2")

        let update = try UserRouter.updateProfile(UserDTO(id: 1, fullName: "Test User")).asURLRequest()
        #expect(update.method == .patch)
        let body = try #require(update.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["full_name"] as? String == "Test User")
    }
}

private enum MinimalRouter: Endpoint {
    case ping

    var baseURL: URL { URL(string: "https://api.example.com")! }
    var path: String { "ping" }
}

private protocol AppEndpoint: Endpoint {}

extension AppEndpoint {
    var baseURL: URL { URL(string: "https://api.example.com/v1")! }
    var jsonEncoder: JSONEncoder { .snakeCaseISO8601 }
}

private enum UserRouter: AppEndpoint {
    case profile
    case posts(userID: Int, page: Int)
    case updateProfile(UserDTO)

    var path: String {
        switch self {
        case .profile, .updateProfile: "me"
        case let .posts(userID, _): "users/\(userID)/posts"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .profile, .posts: .get
        case .updateProfile: .patch
        }
    }

    var task: RequestTask {
        switch self {
        case .profile: .plain
        case let .posts(_, page): .query(["page": page])
        case let .updateProfile(body): .json(body)
        }
    }
}
