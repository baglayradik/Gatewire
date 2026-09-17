internal import Alamofire
internal import Foundation

/// Схема авторизации в рамках одного ``APIClient``.
protocol AuthScheme: Sendable {
    /// Хосты, на которые разрешено отправлять учётные данные. `nil` — любые.
    var allowedHosts: Set<String>? { get }

    /// Подготавливает схему к работе, например читает учётные данные из хранилища.
    func prepare() async

    /// Интерцептор для запроса.
    func interceptor(isOptional: Bool) -> any RequestInterceptor

    /// Сохраняет учётные данные.
    func signIn(_ credential: any Sendable) async throws

    /// Удаляет учётные данные.
    func signOut() async throws

    /// Есть ли сейчас учётные данные.
    func isAuthenticated() async -> Bool

    /// Текущие учётные данные.
    func credential() async -> (any Sendable)?
}

extension AuthScheme {
    /// Разрешено ли отправлять учётные данные на этот адрес.
    func allows(url: URL?) -> Bool {
        guard let allowedHosts else { return true }
        guard let host = url?.host?.lowercased() else { return false }

        return allowedHosts.contains { allowedHost in
            let allowedHost = allowedHost.lowercased()

            if allowedHost.hasPrefix("*.") {
                let suffix = allowedHost.dropFirst()
                return host == suffix.dropFirst() || host.hasSuffix(suffix)
            }

            return host == allowedHost
        }
    }
}

/// Схема без собственного хранилища: токен, ключ API, Basic или свой интерцептор.
struct AdapterAuthScheme: AuthScheme {
    let allowedHosts: Set<String>?
    let requiredInterceptor: any RequestInterceptor
    let optionalInterceptor: any RequestInterceptor
    let hasCredential: @Sendable () async -> Bool

    func prepare() async {}

    func interceptor(isOptional: Bool) -> any RequestInterceptor {
        isOptional ? optionalInterceptor : requiredInterceptor
    }

    func signIn(_ credential: any Sendable) async throws {
        throw UsageError(
            "Эта стратегия авторизации не хранит учётные данные: обновите их в источнике, который передан в стратегию."
        )
    }

    func signOut() async throws {
        throw UsageError(
            "Эта стратегия авторизации не хранит учётные данные: удалите их в источнике, который передан в стратегию."
        )
    }

    func isAuthenticated() async -> Bool {
        await hasCredential()
    }

    func credential() async -> (any Sendable)? {
        nil
    }
}

/// Схема с учётными данными в хранилище и обновлением токена.
final class RefreshableAuthScheme<Credential: RefreshableCredential>: AuthScheme {
    let allowedHosts: Set<String>?

    private let interceptor: AuthenticationInterceptor<RefreshingAuthenticator<Credential>>
    private let store: any CredentialStore<Credential>
    private let scheme: AuthSchemeID
    private let events: AuthEventBroadcaster
    private let loadTask = LockedState<Task<Void, Never>?>(nil)

    init(
        store: any CredentialStore<Credential>,
        refresher: any CredentialRefresher<Credential>,
        refreshStatusCodes: Set<Int>,
        allowedHosts: Set<String>?,
        scheme: AuthSchemeID,
        events: AuthEventBroadcaster
    ) {
        self.store = store
        self.allowedHosts = allowedHosts
        self.scheme = scheme
        self.events = events
        self.interceptor = AuthenticationInterceptor(
            authenticator: RefreshingAuthenticator(
                refresher: refresher,
                store: store,
                refreshStatusCodes: refreshStatusCodes,
                scheme: scheme,
                events: events
            )
        )
    }

    func prepare() async {
        let task = loadTask.withValue { state -> Task<Void, Never> in
            if let task = state {
                return task
            }

            let task = Task { [store, interceptor, scheme, events] in
                do {
                    if let credential = try await store.load(), interceptor.credential == nil {
                        interceptor.credential = credential
                    }
                } catch {
                    events.send(.storeFailed(scheme: scheme, error: error))
                }
            }
            state = task
            return task
        }

        await task.value
    }

    func interceptor(isOptional: Bool) -> any RequestInterceptor {
        isOptional ? OptionalAuthenticationInterceptor(base: interceptor) : interceptor
    }

    func signIn(_ credential: any Sendable) async throws {
        guard let credential = credential as? Credential else {
            throw UsageError("Схема \(scheme) ожидает учётные данные типа \(Credential.self).")
        }

        await prepare()
        try await store.save(credential)
        interceptor.credential = credential
        events.send(.signedIn(scheme: scheme))
    }

    func signOut() async throws {
        await prepare()
        interceptor.credential = nil
        try await store.clear()
        events.send(.signedOut(scheme: scheme))
    }

    func isAuthenticated() async -> Bool {
        await prepare()

        return interceptor.credential != nil
    }

    func credential() async -> (any Sendable)? {
        await prepare()

        return interceptor.credential
    }
}
