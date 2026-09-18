import Foundation
import Gatewire

/// Точка доступа приложения к DummyJSON.
///
/// Показывает типичную настройку Gatewire: один клиент без авторизации для входа и обновления
/// токена и один основной клиент со стратегией `.refreshable`.
struct DemoAPI: Sendable {
    /// Время жизни токена в минутах. Короткое, чтобы обновление было видно в журнале событий.
    static let tokenLifetimeMinutes = 1

    let client: APIClient

    static func live() -> DemoAPI {
        let publicClient = APIClient {
            $0.logging = .basic
        }

        let client = APIClient {
            $0.auth = .refreshable(
                store: KeychainCredentialStore<SessionCredential>(service: "com.example.GatewireDemo.session"),
                refresher: SessionRefresher(publicClient: publicClient, lifetimeMinutes: tokenLifetimeMinutes),
                allowedHosts: ["dummyjson.com"]
            )
            #if DEBUG
            $0.logging = .headers
            #else
            $0.logging = .basic
            #endif
        }

        return DemoAPI(client: client)
    }

    // MARK: - Авторизация

    func signIn(username: String, password: String) async throws -> UserProfile {
        let request = LoginRequest(
            username: username,
            password: password,
            expiresInMins: Self.tokenLifetimeMinutes
        )
        let tokens = try await client.request(AuthRouter.login(request), as: TokenPair.self)

        try await client.auth.signIn(
            with: SessionCredential(tokens: tokens, lifetimeMinutes: Self.tokenLifetimeMinutes)
        )

        return try await profile()
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func isSignedIn() async -> Bool {
        await client.auth.isAuthenticated()
    }

    func authEvents() -> AsyncStream<AuthEvent> {
        client.auth.events()
    }

    // MARK: - Данные

    /// Авторизованная зона: без токена запрос не отправится.
    func profile() async throws(NetworkError) -> UserProfile {
        try await client.request(AuthRouter.me)
    }

    /// Публичная зона: токен не отправляется, даже если пользователь вошёл.
    func products(skip: Int, limit: Int = 20) async throws(NetworkError) -> ProductPage {
        try await client.request(ProductRouter.page(skip: skip, limit: limit))
    }
}
