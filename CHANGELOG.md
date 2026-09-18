# Журнал изменений

Все заметные изменения проекта фиксируются в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
проект следует [семантическому версионированию](https://semver.org/lang/ru/spec/v2.0.0.html).
До версии `1.0.0` minor-версии могут содержать ломающие изменения.

## [Unreleased]

## [0.1.0] - 2026-09-18

Первый публичный выпуск.

### Добавлено

#### Запросы

- Протокол `Endpoint` на основе `URLRequestConvertible`: запросы описываются роутерами, тип ответа задаётся в месте вызова.
- `RequestTask`: параметры в строке запроса, JSON, form, multipart и произвольные тела; `Endpoint.jsonEncoder` и `Endpoint.formEncoder` для формата API.
- `APIClient` с методами `request(_:as:)`, `request(_:decoder:)`, `response`, `send` и `data` на `async`/`await` с typed throws.
- `APIClient.upload` с прогрессом отправки и `APIClient.download` в файл с прогрессом скачивания.
- `APIConfiguration` со значениями по умолчанию и настройкой через `APIClient { $0... }`.
- Типы Alamofire, входящие в публичный API, доступны через `import Gatewire`.

#### Ответы и ошибки

- `ResponseDecoder` и `ResponseDecodingContext` для своих форматов ответа.
- `DecodableResponseDecoder`, `StringResponseDecoder`, `NestedResponseDecoder` (`.nested(_:at:)`) и `EnvelopeDecoder` с протоколом `ResponseEnvelope` (`.envelope(_:)`).
- Пресеты `JSONDecoder.snakeCaseISO8601` и `JSONEncoder.snakeCaseISO8601`.
- `NetworkError` и протокол `APIErrorMapper` для доменных ошибок API.

#### Авторизация

- `Endpoint.authorization` и `AuthorizationRequirement`: запросы из авторизованной и неавторизованной зоны.
- `AuthStrategy`: стратегии `bearer`, `apiKey`, `basic`, `oauth2`, `refreshable` и `custom`; несколько схем в одном клиенте.
- Обновление токена одним запросом на все параллельные запросы через `AuthenticationInterceptor` Alamofire.
- Ограничение хостов (`allowedHosts`), на которые отправляются учётные данные.
- `RefreshableCredential`, `CredentialRefresher`, `OAuth2Credential` и `OAuth2TokenRefresher` по RFC 6749.
- `CredentialStore` с реализациями `KeychainCredentialStore` и `InMemoryCredentialStore`.
- `APIClient.auth` (`AuthController`): вход, выход, текущие учётные данные и поток событий `AuthEvent`.

#### Надёжность и безопасность

- `RetryConfiguration`: повторы идемпотентных запросов с экспоненциальной задержкой; 401 и 403 не повторяются.
- `LoggingConfiguration`: логирование с маскированием секретов в адресах, заголовках, JSON- и form-телах.
- `RedirectConfiguration`: при переходе на другой хост убираются `Authorization`, `Cookie` и подобные заголовки.
- `ServerTrustConfiguration`: закрепление сертификатов и публичных ключей, в том числе из бандла.
- `APIConfiguration.eventMonitors` для своих мониторов событий Alamofire.

#### Тестирование

- Модуль `GatewireTesting`: `StubNetwork` с заглушками по эндпоинтам, путям и условиям, очередями ответов, ошибками сети, задержками, перенаправлениями и записью запросов; изоляция параллельных тестов.
- `StubCredentialRefresher` для тестов авторизации с обновлением токена.

#### Документация и инфраструктура

- Статьи документации «Работа с разными форматами API», «Авторизация» и «Надёжность и безопасность».
- Пример приложения `Examples/GatewireDemo` на SwiftUI с публичным API DummyJSON.
- CI, проверка ломающих изменений API, публикация релизов по тегам, файлы сообщества.

[Unreleased]: https://github.com/baglayradik/Gatewire/compare/0.1.0...HEAD
[0.1.0]: https://github.com/baglayradik/Gatewire/releases/tag/0.1.0
