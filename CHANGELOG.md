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
