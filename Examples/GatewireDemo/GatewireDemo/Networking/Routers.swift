import Foundation
import Gatewire

/// Общие параметры всех роутеров DummyJSON: адрес API задаётся один раз.
protocol DummyJSONEndpoint: Endpoint {}

extension DummyJSONEndpoint {
    var baseURL: URL { URL(string: "https://dummyjson.com")! }
}

/// Вход, обновление токена и профиль. В одном роутере — обе зоны.
enum AuthRouter: DummyJSONEndpoint {
    case login(LoginRequest)
    case refresh(RefreshRequest)
    case me

    var path: String {
        switch self {
        case .login: "auth/login"
        case .refresh: "auth/refresh"
        case .me: "auth/me"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .login, .refresh: .post
        case .me: .get
        }
    }

    var task: RequestTask {
        switch self {
        case let .login(body): .json(body)
        case let .refresh(body): .json(body)
        case .me: .plain
        }
    }

    var authorization: AuthorizationRequirement {
        switch self {
        case .login, .refresh: .none
        case .me: .required
        }
    }
}

/// Каталог товаров — публичная зона, токен не нужен.
enum ProductRouter: DummyJSONEndpoint {
    case page(skip: Int, limit: Int)

    var path: String { "products" }

    var task: RequestTask {
        switch self {
        case let .page(skip, limit):
            .query(ProductPageQuery(skip: skip, limit: limit, select: "title,price,thumbnail"))
        }
    }

    var authorization: AuthorizationRequirement { .none }
}

// MARK: - Модели

struct LoginRequest: Encodable, Sendable {
    let username: String
    let password: String
    let expiresInMins: Int
}

struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
    let expiresInMins: Int
}

struct TokenPair: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct UserProfile: Decodable, Sendable, Equatable {
    let id: Int
    let username: String
    let firstName: String
    let lastName: String
    let email: String
    let image: URL?

    var fullName: String { "\(firstName) \(lastName)" }
}

struct ProductPageQuery: Encodable, Sendable {
    let skip: Int
    let limit: Int
    let select: String
}

struct ProductPage: Decodable, Sendable {
    let products: [Product]
    let total: Int
    let skip: Int
    let limit: Int
}

struct Product: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let price: Double
    let thumbnail: URL?
}
