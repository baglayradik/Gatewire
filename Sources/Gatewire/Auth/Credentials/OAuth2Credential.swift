internal import Alamofire
public import Foundation

/// Учётные данные OAuth 2.0: access-токен и, при наличии, refresh-токен.
public struct OAuth2Credential: RefreshableCredential, Equatable {
    /// Access-токен.
    public var accessToken: String

    /// Тип токена из ответа сервера, обычно `Bearer`.
    public var tokenType: String

    /// Refresh-токен. Без него обновление невозможно.
    public var refreshToken: String?

    /// Момент истечения access-токена или `nil`, если сервер его не сообщил.
    public var expiresAt: Date?

    /// Разрешения токена из ответа сервера.
    public var scope: String?

    /// За сколько секунд до истечения токен считается требующим обновления. По умолчанию 60.
    public var refreshLeeway: TimeInterval

    /// Создаёт учётные данные.
    public init(
        accessToken: String,
        tokenType: String = "Bearer",
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        scope: String? = nil,
        refreshLeeway: TimeInterval = 60
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
        self.refreshLeeway = refreshLeeway
    }

    /// Создаёт учётные данные из ответа token endpoint.
    ///
    /// - Parameters:
    ///   - response: Ответ сервера.
    ///   - issuedAt: Момент получения ответа, от которого считается `expires_in`. По умолчанию текущий.
    ///   - previousRefreshToken: Прежний refresh-токен. Используется, если сервер не прислал новый.
    ///   - refreshLeeway: Запас времени до истечения токена. По умолчанию 60 секунд.
    public init(
        _ response: OAuth2TokenResponse,
        issuedAt: Date = Date(),
        previousRefreshToken: String? = nil,
        refreshLeeway: TimeInterval = 60
    ) {
        self.init(
            accessToken: response.accessToken,
            tokenType: response.tokenType ?? "Bearer",
            refreshToken: response.refreshToken ?? previousRefreshToken,
            expiresAt: response.expiresIn.map { issuedAt.addingTimeInterval($0) },
            scope: response.scope,
            refreshLeeway: refreshLeeway
        )
    }

    /// Значение заголовка `Authorization`.
    public var authorizationValue: String {
        let tokenType = tokenType.lowercased() == "bearer" ? "Bearer" : tokenType
        return "\(tokenType) \(accessToken)"
    }

    public var requiresRefresh: Bool {
        guard let expiresAt else { return false }

        return Date() >= expiresAt.addingTimeInterval(-refreshLeeway)
    }

    public func apply(to request: inout URLRequest) {
        request.headers.update(.authorization(authorizationValue))
    }

    public func isApplied(to request: URLRequest) -> Bool {
        request.headers["Authorization"] == authorizationValue
    }
}

/// Ответ token endpoint по RFC 6749.
public struct OAuth2TokenResponse: Codable, Sendable, Equatable {
    /// Access-токен.
    public let accessToken: String

    /// Тип токена.
    public let tokenType: String?

    /// Время жизни токена в секундах.
    public let expiresIn: TimeInterval?

    /// Refresh-токен.
    public let refreshToken: String?

    /// Разрешения токена.
    public let scope: String?

    /// Создаёт ответ.
    public init(
        accessToken: String,
        tokenType: String? = nil,
        expiresIn: TimeInterval? = nil,
        refreshToken: String? = nil,
        scope: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

/// Ошибка обновления токена OAuth 2.0.
public enum OAuth2Error: Error, Sendable, Equatable {
    /// У учётных данных нет refresh-токена, обновить их невозможно.
    case missingRefreshToken

    /// Сервер вернул ошибку по RFC 6749, например `invalid_grant`.
    case server(code: String, description: String?, statusCode: Int)

    /// Ответ token endpoint не удалось разобрать.
    case unexpectedResponse(statusCode: Int)
}
