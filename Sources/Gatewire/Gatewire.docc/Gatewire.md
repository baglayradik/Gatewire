# ``Gatewire``

Переиспользуемый сетевой слой на основе Alamofire и Swift Concurrency с эндпоинтами в виде роутеров и подключаемой авторизацией.

## Обзор

Gatewire позволяет описывать API роутерами, реализующими `URLRequestConvertible`, отправлять запросы через `async`/`await` и для каждого запроса выбирать, выполняется он с авторизацией или без. Стратегия авторизации — Bearer token, OAuth 2.0, API key, Basic или своя — настраивается один раз для клиента.

> Important: Gatewire находится в ранней разработке (`0.x`). До версии `1.0.0` публичный API может меняться между minor-версиями.

## Topics

### Статьи

- <doc:APIFormats>

### Описание запросов

- ``Endpoint``
- ``RequestTask``

### Выполнение запросов

- ``APIClient``
- ``APIConfiguration``
- ``APIResponse``
- ``TransferProgress``
- ``TransferProgressHandler``

### Разбор ответов

- ``ResponseDecoder``
- ``ResponseDecodingContext``
- ``DecodableResponseDecoder``
- ``NestedResponseDecoder``
- ``EnvelopeDecoder``
- ``ResponseEnvelope``
- ``StringResponseDecoder``

### Ошибки

- ``NetworkError``
- ``APIErrorMapper``
