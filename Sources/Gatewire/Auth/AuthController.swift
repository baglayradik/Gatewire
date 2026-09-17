/// Управление учётными данными клиента.
///
/// Доступен как ``APIClient/auth``.
///
/// ```swift
/// // после запроса входа без авторизации
/// try await client.auth.signIn(with: OAuth2Credential(tokens))
///
/// // реакция на конец сессии
/// for await event in client.auth.events() {
///     if case .refreshFailed = event {
///         await router.showLogin()
///     }
/// }
///
/// try await client.auth.signOut()
/// ```
public final class AuthController: Sendable {
    private let schemes: [AuthSchemeID: any AuthScheme]
    private let broadcaster: AuthEventBroadcaster

    init(schemes: [AuthSchemeID: any AuthScheme], broadcaster: AuthEventBroadcaster) {
        self.schemes = schemes
        self.broadcaster = broadcaster
    }

    /// Поток событий авторизации.
    ///
    /// Каждый вызов создаёт отдельный поток, поэтому событие получают все подписчики.
    /// События, произошедшие до подписки, не доставляются.
    public func events() -> AsyncStream<AuthEvent> {
        broadcaster.events()
    }

    /// Сохраняет учётные данные и применяет их к последующим запросам.
    ///
    /// - Parameters:
    ///   - credential: Учётные данные.
    ///   - scheme: Схема авторизации. По умолчанию ``AuthSchemeID/default``.
    /// - Throws: Ошибку хранилища, либо ошибку использования, если схема не настроена,
    ///   не хранит учётные данные или ожидает другой их тип.
    public func signIn(with credential: some RefreshableCredential, scheme: AuthSchemeID = .default) async throws {
        try await self.scheme(scheme).signIn(credential)
    }

    /// Удаляет учётные данные схемы.
    ///
    /// - Parameter scheme: Схема авторизации. По умолчанию ``AuthSchemeID/default``.
    public func signOut(scheme: AuthSchemeID = .default) async throws {
        try await self.scheme(scheme).signOut()
    }

    /// Есть ли у схемы учётные данные.
    ///
    /// - Parameter scheme: Схема авторизации. По умолчанию ``AuthSchemeID/default``.
    public func isAuthenticated(scheme: AuthSchemeID = .default) async -> Bool {
        guard let scheme = schemes[scheme] else { return false }

        return await scheme.isAuthenticated()
    }

    /// Текущие учётные данные схемы.
    ///
    /// - Parameters:
    ///   - type: Тип учётных данных.
    ///   - scheme: Схема авторизации. По умолчанию ``AuthSchemeID/default``.
    public func credential<Credential: RefreshableCredential>(
        as type: Credential.Type = Credential.self,
        scheme: AuthSchemeID = .default
    ) async -> Credential? {
        guard let scheme = schemes[scheme] else { return nil }

        return await scheme.credential() as? Credential
    }

    private func scheme(_ id: AuthSchemeID) throws -> any AuthScheme {
        guard let scheme = schemes[id] else {
            throw UsageError("Схема авторизации \(id) не настроена в APIConfiguration.")
        }

        return scheme
    }
}
