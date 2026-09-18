public import Foundation

/// Правило заглушки: какие запросы оно перехватывает и что на них отвечает.
///
/// Создаётся методами `on` у ``StubNetwork``. Ответ по умолчанию — `200` с пустым телом.
///
/// ```swift
/// network.on(UserRouter.profile).respond(json: #"{"id": 1}"#)
/// network.on(FeedRouter.page(1)).respond(with: .status(503), .json("[]"))  // сначала 503, потом 200
/// ```
public final class StubRoute: Sendable {
    private enum Responder {
        case sequence([StubResponse])
        case dynamic(@Sendable (URLRequest) async throws -> StubResponse)
    }

    private struct State {
        var responder: Responder = .sequence([.status(200)])
        var requests: [URLRequest] = []
    }

    let matches: @Sendable (URLRequest) -> Bool
    private let state = LockedValue(State())

    init(matches: @escaping @Sendable (URLRequest) -> Bool) {
        self.matches = matches
    }

    /// Запросы, которые обработало это правило, в порядке поступления.
    public var requests: [URLRequest] {
        state.withValue { $0.requests }
    }

    /// Сколько раз правило сработало.
    public var callCount: Int {
        requests.count
    }

    /// Отвечает указанными ответами по очереди; последний повторяется для всех следующих запросов.
    @discardableResult
    public func respond(with responses: StubResponse...) -> StubRoute {
        respond(with: responses)
    }

    /// Отвечает указанными ответами по очереди; последний повторяется для всех следующих запросов.
    @discardableResult
    public func respond(with responses: [StubResponse]) -> StubRoute {
        precondition(responses.isEmpty == false, "Нужен хотя бы один ответ заглушки.")

        state.withValue { $0.responder = .sequence(responses) }
        return self
    }

    /// Отвечает JSON-телом из строки.
    @discardableResult
    public func respond(json: String, statusCode: Int = 200) -> StubRoute {
        respond(with: .json(json, statusCode: statusCode))
    }

    /// Отвечает указанным кодом с пустым телом.
    @discardableResult
    public func respond(statusCode: Int) -> StubRoute {
        respond(with: .status(statusCode))
    }

    /// Отвечает ошибкой сети.
    @discardableResult
    public func fail(with code: URLError.Code) -> StubRoute {
        respond(with: .failure(code))
    }

    /// Формирует ответ в замыкании, например в зависимости от заголовков запроса.
    ///
    /// Ошибка, брошенная из замыкания, приходит клиенту как ошибка сети.
    @discardableResult
    public func respond(using responder: @escaping @Sendable (URLRequest) async throws -> StubResponse) -> StubRoute {
        state.withValue { $0.responder = .dynamic(responder) }
        return self
    }

    func response(for request: URLRequest) async throws -> StubResponse {
        let responder = state.withValue { state -> Responder in
            state.requests.append(request)

            guard case var .sequence(responses) = state.responder else {
                return state.responder
            }
            let next = responses.count > 1 ? responses.removeFirst() : responses[0]
            state.responder = .sequence(responses)
            return .sequence([next])
        }

        switch responder {
        case let .sequence(responses):
            return responses[0]

        case let .dynamic(respond):
            return try await respond(request)
        }
    }
}
