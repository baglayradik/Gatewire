# Надёжность и безопасность

Повторы запросов, логирование без утечки секретов, перенаправления и закрепление сертификатов.

## Обзор

Всё это настраивается в ``APIConfiguration`` и действует на все запросы клиента.
Значения по умолчанию рассчитаны на то, чтобы их не приходилось менять: повторяются только
идемпотентные запросы, логирование выключено, а чувствительные заголовки не уходят
на посторонние хосты при перенаправлении.

## Повторы запросов

По умолчанию запрос повторяется до двух раз с задержками 1 и 2 секунды, если метод идемпотентный
(GET, HEAD, OPTIONS, PUT, DELETE, TRACE), а ошибка имеет смысл повторять: код ответа 408, 500, 502,
503 или 504, либо обрыв соединения, таймаут и другие сетевые сбои.

```swift
let client = APIClient {
    $0.retry.limit = 3
    $0.retry.methods.insert(.post)      // если POST в вашем API идемпотентен
    $0.retry.statusCodes.insert(429)    // если сервер просит подождать этим кодом
}

let withoutRetries = APIClient { $0.retry = .disabled }
```

Ответы 401 и 403 повторами **не** обрабатываются: это задача авторизации. При настроенной
стратегии с обновлением токена Gatewire обновит токен и повторит запрос сам — см. <doc:Authorization>.
Ошибки сборки и кодирования запроса тоже не повторяются: их результат не изменится.

## Логирование

Логирование выключено по умолчанию. Уровни: ``LoggingConfiguration/Level/basic`` (метод, адрес,
код ответа, длительность), ``LoggingConfiguration/Level/headers`` и
``LoggingConfiguration/Level/verbose`` (плюс тела запроса и ответа).

```swift
let client = APIClient {
    #if DEBUG
    $0.logging = .verbose
    #else
    $0.logging = .basic
    #endif
}
```

Секреты маскируются на всех уровнях: значения заголовков из ``LoggingConfiguration/redactedHeaders``
(`Authorization`, `Cookie`, `X-API-Key` и другие) и значения параметров из
``LoggingConfiguration/redactedParameters`` (`access_token`, `refresh_token`, `password`,
`client_secret` и другие) заменяются на `<скрыто>` — в строке запроса, в заголовках,
в JSON-телах и в form-телах. Оба списка можно дополнить своими именами:

```swift
$0.logging.redactedHeaders.insert("x-tenant-secret")
$0.logging.redactedParameters.insert("card_number")
```

По умолчанию лог идёт в `os.Logger` подсистемы `Gatewire`. Свой приёмник задаётся через
``LoggingConfiguration/sink`` — например, чтобы отправлять строки в свою систему логирования:

```swift
$0.logging.sink = { message in AppLog.network.debug(message) }
```

Для метрик и своей аналитики можно добавить мониторы Alamofire в ``APIConfiguration/eventMonitors``.

## Перенаправления

`URLSession` переносит заголовки запроса на новый адрес, поэтому при перенаправлении на посторонний
хост токен мог бы уйти третьей стороне. По умолчанию Gatewire следует за перенаправлениями,
но убирает `Authorization`, `Cookie` и другие чувствительные заголовки, если хост изменился.

```swift
$0.redirects = .follow                            // сохранять все заголовки
$0.redirects = .doNotFollow                       // не следовать: ответ 3xx вернётся как есть
$0.redirects = .followStripping(["x-tenant"])     // свой список заголовков
$0.redirects = .custom(Redirector(behavior: .modify { task, request, response in request }))
```

## Закрепление сертификатов

```swift
let client = APIClient {
    $0.serverTrust = .pinnedCertificates(hosts: ["api.example.com"])
}
```

Сертификаты берутся из файлов `.cer`, `.crt` и `.der` в бандле приложения. Есть вариант
с закреплением публичных ключей — он устойчивее к перевыпуску сертификата:

```swift
$0.serverTrust = .pinnedPublicKeys(hosts: ["api.example.com"])
```

По умолчанию `allHostsMustBeEvaluated` равно `true`: запрос к хосту, для которого правила нет,
завершится ошибкой. Это защищает от случайного обращения к незакреплённому хосту. Если приложение
ходит и на другие хосты, передайте `allHostsMustBeEvaluated: false` или опишите правила для всех хостов.

> Important: Перед закреплением продумайте смену сертификата. Закрепите резервный сертификат
> или ключ заранее, иначе после перевыпуска приложение перестанет работать до обновления в App Store.
