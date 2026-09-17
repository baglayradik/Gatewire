# Авторизация

Как выполнять запросы из авторизованной и неавторизованной зоны и настроить обновление токена.

## Обзор

Стратегия авторизации задаётся один раз в ``APIConfiguration/auth``, а каждый эндпоинт указывает
в ``Endpoint/authorization``, нужны ли ему учётные данные. Запросы с ``AuthorizationRequirement/none``
никогда не получают токен, даже если пользователь авторизован.

## Две зоны в одном роутере

```swift
enum AuthRouter: Endpoint {
    case signIn(SignInRequest)
    case signOut

    var baseURL: URL { AppConfig.apiBaseURL }
    var method: HTTPMethod { .post }

    var path: String {
        switch self {
        case .signIn:  "auth/sign-in"
        case .signOut: "auth/sign-out"
        }
    }

    var task: RequestTask {
        switch self {
        case let .signIn(body): .json(body)
        case .signOut:          .plain
        }
    }

    var authorization: AuthorizationRequirement {
        switch self {
        case .signIn:  .none      // вход выполняется без токена
        case .signOut: .required  // выход — с токеном
        }
    }
}
```

| Требование | Поведение |
|---|---|
| ``AuthorizationRequirement/none`` | Запрос без учётных данных. |
| ``AuthorizationRequirement/required`` | Учётные данные обязательны. Если их нет, запрос не отправляется и приходит ``NetworkError/unauthenticated``. |
| ``AuthorizationRequirement/optional`` | Учётные данные добавляются, только если они есть. |
| ``AuthorizationRequirement/inherit`` | Требование берётся из ``APIConfiguration/defaultAuthorization``. Значение по умолчанию. |

Если ``Endpoint/authorization`` не указывать, работает ``AuthorizationRequirement/inherit``:
запрос требует авторизации, когда стратегия настроена, и выполняется без неё, когда стратегий нет.

## Стратегии

| Стратегия | Когда подходит |
|---|---|
| ``AuthStrategy/bearer(allowedHosts:token:)`` | Токен хранит само приложение. |
| ``AuthStrategy/apiKey(_:name:in:allowedHosts:)`` | Ключ API в заголовке или строке запроса. |
| ``AuthStrategy/basic(username:password:allowedHosts:)`` | HTTP Basic. |
| ``AuthStrategy/oauth2(tokenURL:clientID:clientSecret:keychainService:keychainAccount:refreshStatusCodes:allowedHosts:)`` | OAuth 2.0: Keychain и обновление токена из коробки. |
| ``AuthStrategy/refreshable(store:refresher:refreshStatusCodes:allowedHosts:)`` | Свой тип учётных данных с обновлением. |
| ``AuthStrategy/custom(_:allowedHosts:isAuthenticated:)`` | Своя логика, например подпись запроса. |

Параметр `allowedHosts` ограничивает хосты, на которые уходят учётные данные. Если роутер обращается
к постороннему хосту, запрос с ``AuthorizationRequirement/required`` не отправится,
а с ``AuthorizationRequirement/optional`` уйдёт без токена. Указывайте его всегда, когда приложение
работает не только со своим API.

## OAuth 2.0

```swift
let client = APIClient {
    $0.auth = .oauth2(
        tokenURL: AppConfig.apiBaseURL.appendingPathComponent("oauth/token"),
        clientID: "ios-app",
        keychainService: "com.company.app.auth",
        allowedHosts: ["api.example.com"]
    )
}

// вход: первый токен получаем запросом без авторизации
let tokens = try await client.request(AuthRouter.signIn(credentials), as: OAuth2TokenResponse.self)
try await client.auth.signIn(with: OAuth2Credential(tokens))

// дальше токен подставляется сам и обновляется при истечении или ответе 401
let profile = try await client.request(UserRouter.profile, as: UserDTO.self)

try await client.auth.signOut()
```

Обновление выполняется **один раз на все параллельные запросы**: остальные ждут результата
и повторяются с новым токеном. Запрос к token endpoint идёт отдельной сессией без авторизации,
поэтому рекурсия невозможна.

## Конец сессии

Если обновить токен не удалось, запросы приходят с ``NetworkError/authenticationFailed(_:)``,
а в поток ``AuthController/events()`` попадает ``AuthEvent/refreshFailed(scheme:error:)``.
Подпишитесь на события один раз при старте приложения:

```swift
Task {
    for await event in client.auth.events() {
        if case .refreshFailed = event {
            try? await client.auth.signOut()
            await router.showLogin()
        }
    }
}
```

Учётные данные при неудачном обновлении не удаляются автоматически: ошибка может быть сетевой,
и тогда следующий запрос попробует обновить токен снова.

## Свой тип учётных данных

Для сессионных токенов и нестандартных схем реализуйте ``RefreshableCredential``
и ``CredentialRefresher``:

```swift
struct SessionCredential: RefreshableCredential {
    let token: String
    let renewToken: String
    let expiresAt: Date

    var requiresRefresh: Bool { Date() >= expiresAt.addingTimeInterval(-60) }

    func apply(to request: inout URLRequest) {
        request.headers.update(name: "X-Session", value: token)
    }

    func isApplied(to request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "X-Session") == token
    }
}

struct SessionRefresher: CredentialRefresher {
    let client: APIClient  // клиент без авторизации

    func refresh(_ credential: SessionCredential) async throws -> SessionCredential {
        let response = try await client.request(
            SessionRouter.renew(token: credential.renewToken),
            as: SessionDTO.self
        )
        return SessionCredential(
            token: response.token,
            renewToken: response.renewToken,
            expiresAt: response.expiresAt
        )
    }
}

let client = APIClient {
    $0.auth = .refreshable(
        store: KeychainCredentialStore<SessionCredential>(service: "com.company.app.session"),
        refresher: SessionRefresher(client: publicClient),
        refreshStatusCodes: [401, 403]
    )
}
```

Клиент для обновления должен выполнять запросы **без авторизации**: используйте отдельный
``APIClient`` без стратегии или эндпоинт с ``AuthorizationRequirement/none``.

## Несколько схем

```swift
extension AuthSchemeID {
    static let payments = AuthSchemeID("payments")
}

let client = APIClient {
    $0.auth = .oauth2(/* пользовательские токены */)
    $0.additionalAuth = [
        .payments: .apiKey(AppConfig.paymentsKey, name: "X-Payments-Key", allowedHosts: ["pay.example.com"])
    ]
}

// в роутере платежей
var authorization: AuthorizationRequirement { .required(.payments) }
```

Вход и выход для конкретной схемы: ``AuthController/signIn(with:scheme:)``
и ``AuthController/signOut(scheme:)``.

## Хранение токенов

- ``KeychainCredentialStore`` хранит учётные данные в Keychain в формате JSON. По умолчанию элемент
  доступен после первой разблокировки устройства и не попадает в резервные копии.
- ``InMemoryCredentialStore`` подходит для тестов и временных сессий.
- Ошибки чтения и записи приходят событием ``AuthEvent/storeFailed(scheme:error:)``: запросы продолжают
  работать с учётными данными из памяти, но после перезапуска приложения они будут потеряны.

Своё хранилище — это реализация ``CredentialStore``, например поверх шифрованного файла.
