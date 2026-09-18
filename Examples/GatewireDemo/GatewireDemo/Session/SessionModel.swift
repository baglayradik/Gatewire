import Foundation
import Gatewire
import Observation

/// Состояние сессии пользователя и журнал событий авторизации.
@MainActor
@Observable
final class SessionModel {
    enum State: Equatable {
        case restoring
        case signedOut
        case signedIn(UserProfile)
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
    }

    private(set) var state: State = .restoring
    private(set) var log: [LogEntry] = []
    private(set) var errorMessage: String?
    private(set) var isBusy = false

    let api: DemoAPI
    private var eventsTask: Task<Void, Never>?

    init(api: DemoAPI) {
        self.api = api
        startListeningToAuthEvents()
    }

    // MARK: - Действия

    func restore() async {
        guard await api.isSignedIn() else {
            state = .signedOut
            return
        }

        await reloadProfile()
    }

    func signIn(username: String, password: String) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let profile = try await api.signIn(username: username, password: password)
            state = .signedIn(profile)
        } catch let error as NetworkError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadProfile() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            state = .signedIn(try await api.profile())
            append("Профиль загружен из авторизованной зоны")
        } catch .unauthenticated {
            state = .signedOut
        } catch {
            errorMessage = error.userMessage
        }
    }

    func signOut() async {
        do {
            try await api.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        state = .signedOut
    }

    // MARK: - События авторизации

    private func startListeningToAuthEvents() {
        let events = api.authEvents()

        eventsTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: AuthEvent) {
        switch event {
        case .signedIn:
            append("Вход выполнен, токен сохранён в Keychain")

        case .refreshed:
            append("Токен истёк и обновлён автоматически")

        case let .refreshFailed(_, error):
            append("Обновить токен не удалось: \(error.localizedDescription)")
            state = .signedOut

        case .signedOut:
            append("Выход выполнен, токен удалён")

        case let .storeFailed(_, error):
            append("Ошибка Keychain: \(error.localizedDescription)")
        }
    }

    private func append(_ text: String) {
        log.insert(LogEntry(text: text), at: 0)
    }
}

extension NetworkError {
    /// Текст ошибки для пользователя.
    var userMessage: String {
        switch self {
        case .transport:
            "Нет соединения с сервером. Проверьте интернет."
        case .unauthenticated:
            "Нужно войти в аккаунт."
        case .authenticationFailed:
            "Сессия истекла, войдите снова."
        case let .unacceptableStatusCode(response, _) where response.statusCode == 400:
            "Неверный логин или пароль."
        case let .unacceptableStatusCode(response, _):
            "Сервер вернул ошибку \(response.statusCode)."
        case .decodingFailed:
            "Не удалось разобрать ответ сервера."
        case .cancelled:
            "Запрос отменён."
        case .invalidRequest, .encodingFailed, .api, .underlying:
            "Что-то пошло не так."
        }
    }
}
