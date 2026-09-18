# Журнал изменений

Все заметные изменения проекта фиксируются в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
проект следует [семантическому версионированию](https://semver.org/lang/ru/spec/v2.0.0.html).
До версии `1.0.0` minor-версии могут содержать ломающие изменения.

## [Unreleased]

### Добавлено

- Каркас пакета с продуктами `Gatewire` и `GatewireTesting`.
- Типы Alamofire, входящие в публичный API, доступны через `import Gatewire`.
- CI, проверка ломающих изменений API, workflow релизов и файлы сообщества.
- Протокол `Endpoint` на основе `URLRequestConvertible` для описания запросов роутерами.
- `RequestTask`: параметры в строке запроса, JSON, form, multipart и произвольные тела.
- `APIClient` с методами `request(_:as:)`, `request(_:decoder:)`, `response`, `send` и `data` на `async`/`await` с typed throws.
- `APIConfiguration`: заголовки по умолчанию, декодер, таймаут, допустимые коды ответа, конфигурация `URLSession`.
- `NetworkError` и протокол `APIErrorMapper` для доменных ошибок API.
- `ResponseDecoder` с реализациями `DecodableResponseDecoder` и `StringResponseDecoder`.
- Пресеты `JSONDecoder.snakeCaseISO8601` и `JSONEncoder.snakeCaseISO8601`.
- `Endpoint.formEncoder` для настройки формата массивов, булевых значений и пробелов в query и form.
- `ResponseDecodingContext`: декодеры ответов получают HTTP-ответ и декодер эндпоинта.
- `NestedResponseDecoder` (`.nested(_:at:)`) для значений, вложенных в ответ по пути из ключей.
- `ResponseEnvelope` и `EnvelopeDecoder` (`.envelope(_:)`) для ответов в обёртке с ошибками в теле.
- `APIClient.upload` с прогрессом отправки и `APIClient.download` в файл с прогрессом скачивания.
- Статья документации «Работа с разными форматами API» с примерами GraphQL и своего декодера.
- `Endpoint.authorization` и `AuthorizationRequirement`: запросы из авторизованной и неавторизованной зоны.
- `AuthStrategy`: стратегии `bearer`, `apiKey`, `basic`, `oauth2`, `refreshable` и `custom`.
- Ограничение хостов (`allowedHosts`), на которые отправляются учётные данные.
- Обновление токена одним запросом на все параллельные запросы через `AuthenticationInterceptor` Alamofire.
- `RefreshableCredential`, `CredentialRefresher`, `OAuth2Credential` и `OAuth2TokenRefresher` по RFC 6749.
- `CredentialStore` с реализациями `KeychainCredentialStore` и `InMemoryCredentialStore`.
- `APIClient.auth` (`AuthController`): вход, выход, текущие учётные данные и поток событий `AuthEvent`.
- `NetworkError.unauthenticated` и `NetworkError.authenticationFailed` в модели ошибок.
- Статья документации «Авторизация».
- `RetryConfiguration`: повторы идемпотентных запросов с экспоненциальной задержкой; 401 и 403 не повторяются.
- `LoggingConfiguration` и логгер с маскированием секретов в адресах, заголовках, JSON- и form-телах.
- `RedirectConfiguration`: по умолчанию при переходе на другой хост убираются `Authorization`, `Cookie` и подобные заголовки.
- `ServerTrustConfiguration`: закрепление сертификатов и публичных ключей, в том числе из бандла.
- `APIConfiguration.eventMonitors` для своих мониторов событий Alamofire.
- Статья документации «Надёжность и безопасность».
