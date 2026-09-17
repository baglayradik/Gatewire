# Работа с разными форматами API

Как описать запросы и разобрать ответы, если API использует не только простой JSON.

## Обзор

Формат запроса задаёт ``RequestTask`` вместе с кодировщиками эндпоинта — ``Endpoint/jsonEncoder``
и ``Endpoint/formEncoder``. Формат ответа задаёт ``ResponseDecoder``, переданный при вызове,
или `DataDecoder` эндпоинта и клиента.

## Параметры и тело запроса

| Задача | ``RequestTask`` |
|---|---|
| Параметры в строке запроса | ``RequestTask/query(_:)`` |
| JSON-тело | ``RequestTask/json(_:)`` |
| Тело `application/x-www-form-urlencoded` | ``RequestTask/form(_:)`` |
| Строка запроса и JSON-тело | ``RequestTask/queryAndJSON(query:body:)`` |
| XML, Protobuf и другие готовые данные | ``RequestTask/raw(_:contentType:)`` |
| Файлы и `multipart/form-data` | ``RequestTask/multipart(_:)`` |

API по-разному кодируют массивы и булевы значения в строке запроса. По умолчанию массив
`ids: [1, 2]` превращается в `ids[]=1&ids[]=2`, а `true` — в `1`. Другой формат задаётся
в ``Endpoint/formEncoder``:

```swift
var formEncoder: URLEncodedFormEncoder {
    URLEncodedFormEncoder(arrayEncoding: .noBrackets, boolEncoding: .literal)  // ids=1&ids=2, true
}
```

Кодировщики, общие для всех роутеров проекта, удобно задать в своём базовом протоколе:

```swift
protocol AppEndpoint: Endpoint {}

extension AppEndpoint {
    var baseURL: URL { AppConfig.apiBaseURL }
    var jsonEncoder: JSONEncoder { .snakeCaseISO8601 }
}
```

## Ответ в формате JSON

``APIClient/request(_:as:)`` декодирует `Decodable`-тип декодером эндпоинта (``Endpoint/decoder``),
а если он не задан — декодером клиента (``APIConfiguration/decoder``). Декодер может быть любым
`DataDecoder`, например `PropertyListDecoder` для API, отдающего property list.

## Ответ в обёртке

Если API возвращает данные внутри общей структуры, есть два способа их извлечь.

**Вложенный ключ** — когда достаточно достать значение по пути и отдельный тип не нужен:

```swift
// { "data": { "items": [ ... ] }, "meta": { ... } }
let posts = try await client.request(
    PostRouter.feed(page: 1),
    decoder: .nested([PostDTO].self, at: "data.items")
)
```

**Обёртка ``ResponseEnvelope``** — когда API сообщает об ошибке в теле успешного ответа.
Ошибка из ``ResponseEnvelope/unwrap()`` приходит как ``NetworkError/api(_:response:data:)``:

```swift
struct ServerEnvelope<Payload: Decodable & Sendable>: ResponseEnvelope {
    let success: Bool
    let data: Payload?
    let error: ServerError?

    func unwrap() throws -> Payload {
        guard success, let data else { throw error ?? ServerError.unknown }
        return data
    }
}

let user = try await client.request(
    UserRouter.profile,
    decoder: .envelope(ServerEnvelope<UserDTO>.self)
)
```

## GraphQL

GraphQL-запрос — это POST с JSON-телом, а ответ — обёртка с полями `data` и `errors`:

```swift
struct GraphQLRequest<Variables: Encodable & Sendable>: Encodable, Sendable {
    let query: String
    let variables: Variables
}

struct GraphQLError: Decodable, Error, Sendable {
    let message: String
}

struct GraphQLResponse<Payload: Decodable & Sendable>: ResponseEnvelope {
    let data: Payload?
    let errors: [GraphQLError]?

    func unwrap() throws -> Payload {
        if let error = errors?.first {
            throw error
        }
        guard let data else {
            throw GraphQLError(message: "Ответ без данных")
        }
        return data
    }
}

enum GraphQLRouter: Endpoint {
    case user(id: String)

    var baseURL: URL { URL(string: "https://api.example.com")! }
    var path: String { "graphql" }
    var method: HTTPMethod { .post }

    var task: RequestTask {
        switch self {
        case let .user(id):
            .json(GraphQLRequest(
                query: "query User($id: ID!) { user(id: $id) { id name } }",
                variables: ["id": id]
            ))
        }
    }
}

let result = try await client.request(
    GraphQLRouter.user(id: "42"),
    decoder: .envelope(GraphQLResponse<UserQueryData>.self)
)
```

## Свой формат ответа

Для XML, Protobuf и других форматов реализуйте ``ResponseDecoder``. Контекст декодирования
содержит HTTP-ответ и декодер данных эндпоинта:

```swift
// Требует подключённого пакета SwiftProtobuf.
struct ProtobufDecoder<Message: SwiftProtobuf.Message & Sendable>: ResponseDecoder {
    func decode(_ data: Data, context: ResponseDecodingContext) throws -> Message {
        try Message(serializedBytes: data)
    }
}

extension ResponseDecoder {
    static func protobuf<Message>(_ type: Message.Type) -> Self where Self == ProtobufDecoder<Message> {
        ProtobufDecoder()
    }
}

let profile = try await client.request(UserRouter.profile, decoder: .protobuf(ProfileMessage.self))
```

Ошибка, брошенная декодером, приходит как ``NetworkError/decodingFailed(_:data:)``.
Чтобы вернуть другую категорию, бросьте готовую ``NetworkError``.

## Ошибки API

- Если сервер сообщает об ошибке **кодом ответа**, реализуйте ``APIErrorMapper`` и задайте его
  в ``APIConfiguration/errorMapper``.
- Если ошибка приходит **в теле успешного ответа**, используйте ``ResponseEnvelope``.

В обоих случаях распознанная ошибка приходит как ``NetworkError/api(_:response:data:)``.

## Загрузка и скачивание файлов

``APIClient/upload(_:as:progress:)`` отправляет тело запроса и сообщает прогресс отправки,
``APIClient/download(_:to:progress:)`` сохраняет ответ в файл и сообщает прогресс скачивания.
Обработчики прогресса вызываются на главном потоке:

```swift
let avatar = try await client.upload(UserRouter.uploadAvatar(jpegData), as: AvatarDTO.self) { progress in
    uploadFraction = progress.fractionCompleted
}

let reportURL = try await client.download(ReportRouter.pdf(id: 42), to: destination) { progress in
    downloadFraction = progress.fractionCompleted
}
```
