public import Alamofire
public import Foundation

/// Способ авторизации запросов.
///
/// Задаётся в ``APIConfiguration/auth``, а для нескольких схем — в ``APIConfiguration/additionalAuth``.
///
/// ```swift
/// let client = APIClient {
///     $0.auth = .oauth2(
///         tokenURL: URL(string: "https://api.example.com/oauth/token")!,
///         clientID: "ios-app",
///         keychainService: "com.company.app.auth",
///         allowedHosts: ["api.example.com"]
///     )
/// }
/// ```
public struct AuthStrategy: Sendable {
    let makeScheme: @Sendable (AuthSchemeContext) -> any AuthScheme

    init(makeScheme: @escaping @Sendable (AuthSchemeContext) -> any AuthScheme) {
        self.makeScheme = makeScheme
    }
}

/// Где передаётся ключ API.
public enum APIKeyLocation: Sendable {
    /// В заголовке запроса.
    case header
    /// В строке запроса.
    case queryParameter
}

/// Данные клиента, доступные стратегии при создании схемы.
struct AuthSchemeContext: Sendable {
    let scheme: AuthSchemeID
    let events: AuthEventBroadcaster
    let sessionConfiguration: @Sendable () -> URLSessionConfiguration
}

extension AuthStrategy {
    /// Токен в заголовке `Authorization: Bearer`, который приложение хранит само.
    ///
    /// Если замыкание вернёт `nil`, запрос с ``AuthorizationRequirement/required`` не отправляется
    /// и приходит ``NetworkError/unauthenticated``.
    ///
    /// - Parameters:
    ///   - allowedHosts: Хосты, на которые разрешено отправлять токен. По умолчанию любые.
    ///   - token: Источник токена.
    public static func bearer(
        allowedHosts: Set<String>? = nil,
        token: @escaping @Sendable () async -> String?
    ) -> AuthStrategy {
        AuthStrategy { _ in
            AdapterAuthScheme(
                allowedHosts: allowedHosts,
                requiredInterceptor: BearerTokenAdapter(isOptional: false, token: token),
                optionalInterceptor: BearerTokenAdapter(isOptional: true, token: token),
                hasCredential: { await token() != nil }
            )
        }
    }

    /// Ключ API в заголовке или в строке запроса.
    ///
    /// - Parameters:
    ///   - key: Значение ключа.
    ///   - name: Имя заголовка или параметра. По умолчанию `X-API-Key`.
    ///   - location: Где передаётся ключ. По умолчанию в заголовке.
    ///   - allowedHosts: Хосты, на которые разрешено отправлять ключ. По умолчанию любые.
    public static func apiKey(
        _ key: String,
        name: String = "X-API-Key",
        in location: APIKeyLocation = .header,
        allowedHosts: Set<String>? = nil
    ) -> AuthStrategy {
        AuthStrategy { _ in
            let adapter = APIKeyAdapter(name: name, key: key, location: location)

            return AdapterAuthScheme(
                allowedHosts: allowedHosts,
                requiredInterceptor: adapter,
                optionalInterceptor: adapter,
                hasCredential: { true }
            )
        }
    }

    /// Заголовок `Authorization: Basic` с логином и паролем.
    ///
    /// - Parameters:
    ///   - username: Логин.
    ///   - password: Пароль.
    ///   - allowedHosts: Хосты, на которые разрешено отправлять учётные данные. По умолчанию любые.
    public static func basic(
        username: String,
        password: String,
        allowedHosts: Set<String>? = nil
    ) -> AuthStrategy {
        AuthStrategy { _ in
            let adapter = BasicAuthAdapter(username: username, password: password)

            return AdapterAuthScheme(
                allowedHosts: allowedHosts,
                requiredInterceptor: adapter,
                optionalInterceptor: adapter,
                hasCredential: { true }
            )
        }
    }

    /// Учётные данные в хранилище с автоматическим обновлением.
    ///
    /// Обновление выполняется один раз на все параллельные запросы: остальные ждут его результата
    /// и повторяются с новым токеном. Управление учётными данными — через ``APIClient/auth``.
    ///
    /// - Parameters:
    ///   - store: Хранилище учётных данных.
    ///   - refresher: Обновление учётных данных.
    ///   - refreshStatusCodes: Коды ответа, при которых токен считается отклонённым. По умолчанию `[401]`.
    ///   - allowedHosts: Хосты, на которые разрешено отправлять учётные данные. По умолчанию любые.
    public static func refreshable<Credential: RefreshableCredential>(
        store: some CredentialStore<Credential>,
        refresher: some CredentialRefresher<Credential>,
        refreshStatusCodes: Set<Int> = [401],
        allowedHosts: Set<String>? = nil
    ) -> AuthStrategy {
        AuthStrategy { context in
            RefreshableAuthScheme(
                store: store,
                refresher: refresher,
                refreshStatusCodes: refreshStatusCodes,
                allowedHosts: allowedHosts,
                scheme: context.scheme,
                events: context.events
            )
        }
    }

    /// OAuth 2.0 с хранением токенов в Keychain и обновлением через token endpoint.
    ///
    /// Первый токен нужно получить самостоятельно, например запросом входа без авторизации,
    /// и передать в ``AuthController/signIn(with:scheme:)``.
    ///
    /// - Parameters:
    ///   - tokenURL: Адрес token endpoint.
    ///   - clientID: Идентификатор клиента.
    ///   - clientSecret: Секрет клиента. Для мобильных приложений обычно `nil`.
    ///   - keychainService: Имя сервиса Keychain, обычно идентификатор приложения.
    ///   - keychainAccount: Имя аккаунта Keychain. По умолчанию `oauth2`.
    ///   - refreshStatusCodes: Коды ответа, при которых токен считается отклонённым. По умолчанию `[401]`.
    ///   - allowedHosts: Хосты, на которые разрешено отправлять токен. По умолчанию любые.
    public static func oauth2(
        tokenURL: URL,
        clientID: String,
        clientSecret: String? = nil,
        keychainService: String,
        keychainAccount: String = "oauth2",
        refreshStatusCodes: Set<Int> = [401],
        allowedHosts: Set<String>? = nil
    ) -> AuthStrategy {
        AuthStrategy { context in
            RefreshableAuthScheme(
                store: KeychainCredentialStore<OAuth2Credential>(
                    service: keychainService,
                    account: keychainAccount
                ),
                refresher: OAuth2TokenRefresher(
                    tokenURL: tokenURL,
                    clientID: clientID,
                    clientSecret: clientSecret,
                    sessionConfiguration: context.sessionConfiguration
                ),
                refreshStatusCodes: refreshStatusCodes,
                allowedHosts: allowedHosts,
                scheme: context.scheme,
                events: context.events
            )
        }
    }

    /// Свой интерцептор Alamofire для нестандартной авторизации, например подписи запроса.
    ///
    /// - Parameters:
    ///   - interceptor: Интерцептор запроса.
    ///   - allowedHosts: Хосты, на которые разрешено отправлять учётные данные. По умолчанию любые.
    ///   - isAuthenticated: Есть ли учётные данные. По умолчанию всегда `true`.
    public static func custom(
        _ interceptor: any RequestInterceptor,
        allowedHosts: Set<String>? = nil,
        isAuthenticated: @escaping @Sendable () async -> Bool = { true }
    ) -> AuthStrategy {
        AuthStrategy { _ in
            AdapterAuthScheme(
                allowedHosts: allowedHosts,
                requiredInterceptor: interceptor,
                optionalInterceptor: interceptor,
                hasCredential: isAuthenticated
            )
        }
    }
}
