# ``GatewireTesting``

Заглушки сети для тестов клиентов на Gatewire: запросы не уходят в интернет, а ответы задаются в тесте.

## Обзор

Подключите модуль к тестовому таргету и создайте ``StubNetwork`` в каждом тесте. Клиент из
``StubNetwork/makeClient(_:)`` работает как настоящий — с авторизацией, декодированием и обработкой
ошибок, — но все его запросы обрабатывают заглушки.

```swift
import Gatewire
import GatewireTesting
import Testing

@Test func showsProfile() async throws {
    let network = StubNetwork()
    network.on(UserRouter.profile).respond(json: #"{"id": 1, "name": "Test"}"#)

    let service = ProfileService(client: network.makeClient())
    let profile = try await service.loadProfile()

    #expect(profile.name == "Test")
    #expect(network.requests(to: UserRouter.profile).count == 1)
}
```

Каждая ``StubNetwork`` изолирована: тесты с одинаковыми адресами запросов могут выполняться параллельно.

## Заглушки

Правило сопоставляется с запросом по эндпоинту, пути или произвольному условию. Если подходят
несколько правил, срабатывает добавленное последним — так общие заглушки удобно переопределять
в конкретном тесте.

```swift
network.on(UserRouter.profile).respond(json: #"{"id": 1}"#)       // метод, адрес и параметры запроса
network.on(.get, path: "/v1/feed").respond(statusCode: 204)        // только путь, любой хост
network.on(where: { $0.url?.host == "cdn.example.com" })           // своё условие
    .respond(with: .data(imageData, contentType: "image/png"))
```

Ответы:

```swift
.respond(with: .json(#"{"id": 1}"#))
.respond(with: try .encoded(user, statusCode: 201))
.respond(with: .status(503), .json("[]"))            // сначала 503, затем 200 для всех следующих
.respond(with: StubResponse.json("{}").delayed(by: 2))
.fail(with: .notConnectedToInternet)
.respond(with: .redirect(to: newURL))
.respond { request in                                 // ответ по содержимому запроса
    request.value(forHTTPHeaderField: "Authorization") == nil ? .status(401) : .json("{}")
}
```

На запросы без подходящей заглушки сеть отвечает ``StubNetwork/unmatchedResponse`` (по умолчанию 404)
и сохраняет их в ``StubNetwork/unmatchedRequests`` — это помогает найти забытую заглушку.

## Проверка запросов

``StubNetwork/requests`` содержит все запросы в порядке отправки, ``StubRoute/requests`` — запросы
конкретного правила. Тело запроса доступно в `httpBody`, даже если оно передавалось потоком:

```swift
let route = network.on(UserRouter.update(changes)).respond(statusCode: 204)
try await service.save(changes)

let body = try #require(route.requests.first?.httpBody)
#expect(try JSONDecoder().decode(UserChanges.self, from: body) == changes)
```

## Авторизация

Для стратегий с обновлением токена есть ``StubCredentialRefresher``:

```swift
let refresher = StubCredentialRefresher(returning: OAuth2Credential(accessToken: "new"))
let client = network.makeClient {
    $0.auth = .refreshable(store: InMemoryCredentialStore(expiredCredential), refresher: refresher)
}

try await client.send(UserRouter.profile)
#expect(await refresher.refreshCount == 1)
```

Если запросы выполняет не клиент из ``StubNetwork/makeClient(_:)``, например `OAuth2TokenRefresher`,
передайте ему ``StubNetwork/sessionConfiguration``.

## Ограничения

- Повторы запросов в клиенте из ``StubNetwork/makeClient(_:)`` отключены, чтобы тесты не ждали
  задержек. Включить их можно в замыкании настройки.
- `URLSession` не сообщает прогресс отправки для подменённых запросов, а прогресс скачивания —
  только на macOS. Прогресс проверяйте на реальной сети.

## Topics

### Сеть и заглушки

- ``StubNetwork``
- ``StubRoute``
- ``StubResponse``

### Авторизация

- ``StubCredentialRefresher``
