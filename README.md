# Gatewire

[![CI](https://github.com/baglayradik/Gatewire/actions/workflows/ci.yml/badge.svg)](https://github.com/baglayradik/Gatewire/actions/workflows/ci.yml)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbaglayradik%2FGatewire%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/baglayradik/Gatewire)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbaglayradik%2FGatewire%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/baglayradik/Gatewire)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Переиспользуемый сетевой слой для Swift-приложений на основе [Alamofire](https://github.com/Alamofire/Alamofire) и Swift Concurrency.

> [!WARNING]
> Gatewire находится в ранней разработке. До версии `1.0.0` публичный API может меняться между minor-версиями.

## Возможности

- **Эндпоинты в виде роутеров.** Группа запросов описывается одним `enum`, реализующим `URLRequestConvertible`. Тип ответа указывается в месте вызова.
- **`async`/`await` везде.** Swift 6 language mode, строгая проверка concurrency, отмена задачи отменяет и сам запрос.
- **Запросы с авторизацией и без.** Каждый эндпоинт указывает, нужны ли ему учётные данные. Запросы без авторизации никогда не получают токен.
- **Подключаемая авторизация.** Bearer token, OAuth 2.0 с единственным обновлением токена на все параллельные запросы, API key, Basic или своя стратегия.
- **Любой формат API.** JSON, form, multipart и произвольные тела запросов. Свои декодеры ответов для обёрток, XML, Protobuf или GraphQL.
- **Создан для использования в разных проектах.** Разумные значения по умолчанию, пресеты в одну строку и модуль `GatewireTesting` для подмены запросов в тестах.

## Требования

| Gatewire | Swift | Xcode | Платформы |
|---|---|---|---|
| 0.x | 6.0+ | 16.0+ | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+ |

## Установка

### Swift Package Manager

В Xcode выберите **File → Add Package Dependencies…** и укажите адрес:

```
https://github.com/baglayradik/Gatewire.git
```

Добавьте `Gatewire` в таргет приложения, а `GatewireTesting` — в тестовый таргет.

Или добавьте зависимость в `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/baglayradik/Gatewire.git", .upToNextMinor(from: "0.1.0")),
],
targets: [
    .target(name: "MyApp", dependencies: ["Gatewire"]),
    .testTarget(name: "MyAppTests", dependencies: ["MyApp", .product(name: "GatewireTesting", package: "Gatewire")]),
]
```

Пока Gatewire в версии `0.x`, используйте `.upToNextMinor`, чтобы ломающие изменения не подтягивались автоматически.

## Быстрый старт

### 1. Опишите запросы роутером

```swift
import Gatewire

enum UserRouter: Endpoint {
    case profile
    case posts(userID: Int, page: Int)
    case updateProfile(UpdateProfileRequest)
    case uploadAvatar(Data)

    var baseURL: URL { URL(string: "https://api.example.com/v1")! }

    var path: String {
        switch self {
        case .profile, .updateProfile: "me"
        case let .posts(userID, _):    "users/\(userID)/posts"
        case .uploadAvatar:            "me/avatar"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .profile, .posts: .get
        case .updateProfile:   .patch
        case .uploadAvatar:    .post
        }
    }

    var task: RequestTask {
        switch self {
        case .profile:                  .plain
        case let .posts(_, page):       .query(["page": page])
        case let .updateProfile(body):  .json(body)
        case let .uploadAvatar(image):
            .multipart { $0.append(image, withName: "avatar", fileName: "avatar.jpg", mimeType: "image/jpeg") }
        }
    }
}
```

Общие для проекта параметры удобно задать один раз в своём протоколе:

```swift
protocol AppEndpoint: Endpoint {}

extension AppEndpoint {
    var baseURL: URL { AppConfig.apiBaseURL }
    var jsonEncoder: JSONEncoder { .snakeCaseISO8601 }
}
```

### 2. Создайте клиент

```swift
let client = APIClient {
    $0.decoder = JSONDecoder.snakeCaseISO8601
    $0.errorMapper = AppErrorMapper()
}
```

### 3. Выполняйте запросы

```swift
let profile = try await client.request(UserRouter.profile, as: UserDTO.self)
let posts: [PostDTO] = try await client.request(UserRouter.posts(userID: 42, page: 1))
try await client.send(UserRouter.uploadAvatar(jpegData))

let response = try await client.response(UserRouter.profile, as: UserDTO.self)
print(response.statusCode, response.headers)
```

Все методы бросают `NetworkError`:

```swift
do {
    try await client.send(UserRouter.updateProfile(changes))
} catch .unacceptableStatusCode(let response, _) where response.statusCode == 409 {
    // конфликт версий
} catch .transport(let urlError) {
    // нет сети, таймаут
} catch {
    // остальные ошибки
}
```

## План развития

- [x] Каркас пакета, CI и файлы сообщества
- [x] Ядро: эндпоинты, `RequestTask`, `APIClient`, модель ошибок
- [ ] Форматы запросов и ответов
- [ ] Стратегии авторизации и хранение учётных данных
- [ ] Повторы запросов, логирование с маскированием секретов, проверка сертификатов сервера
- [ ] Модуль `GatewireTesting`
- [ ] Документация и пример приложения
- [ ] `1.0.0`

## Участие в разработке

Мы рады любому участию — подробности в [CONTRIBUTING.md](CONTRIBUTING.md). Об уязвимостях сообщайте приватно, как описано в [SECURITY.md](SECURITY.md).

## Лицензия

Gatewire распространяется по лицензии MIT. Подробности в файле [LICENSE](LICENSE).
