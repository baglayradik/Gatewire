/// Событие жизненного цикла учётных данных.
///
/// Поток событий возвращает ``AuthController/events()``.
public enum AuthEvent: Sendable {
    /// Учётные данные сохранены через ``AuthController/signIn(with:scheme:)``.
    case signedIn(scheme: AuthSchemeID)

    /// Токен успешно обновлён.
    case refreshed(scheme: AuthSchemeID)

    /// Обновить токен не удалось. Обычно это значит, что сессия закончилась и нужен повторный вход.
    case refreshFailed(scheme: AuthSchemeID, error: any Error)

    /// Учётные данные удалены через ``AuthController/signOut(scheme:)``.
    case signedOut(scheme: AuthSchemeID)

    /// Не удалось прочитать или записать учётные данные в хранилище.
    ///
    /// Запросы продолжают работать с учётными данными из памяти, но после перезапуска
    /// приложения они могут быть потеряны.
    case storeFailed(scheme: AuthSchemeID, error: any Error)
}

/// Рассылает события авторизации всем подписчикам.
final class AuthEventBroadcaster: Sendable {
    private struct State {
        var nextID = 0
        var continuations: [Int: AsyncStream<AuthEvent>.Continuation] = [:]
    }

    private let state = LockedState(State())

    func events() -> AsyncStream<AuthEvent> {
        AsyncStream { continuation in
            let id = state.withValue { state -> Int in
                let id = state.nextID
                state.nextID += 1
                state.continuations[id] = continuation
                return id
            }

            continuation.onTermination = { [state] _ in
                state.withValue { $0.continuations[id] = nil }
            }
        }
    }

    func send(_ event: AuthEvent) {
        let continuations = self.state.withValue { Array($0.continuations.values) }
        for continuation in continuations {
            continuation.yield(event)
        }
    }
}
