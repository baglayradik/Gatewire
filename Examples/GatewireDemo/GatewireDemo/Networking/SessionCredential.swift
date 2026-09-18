import Foundation
import Gatewire

/// Учётные данные DummyJSON.
///
/// Формат ответа DummyJSON отличается от RFC 6749 (поля `accessToken` и `refreshToken`,
/// нет `expires_in`), поэтому вместо готовой стратегии `.oauth2` используется своя пара
/// ``RefreshableCredential`` и ``CredentialRefresher``.
struct SessionCredential: RefreshableCredential {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    init(tokens: TokenPair, lifetimeMinutes: Int, issuedAt: Date = Date()) {
        self.accessToken = tokens.accessToken
        self.refreshToken = tokens.refreshToken
        self.expiresAt = issuedAt.addingTimeInterval(TimeInterval(lifetimeMinutes * 60))
    }

    /// Токен обновляется заранее, за 10 секунд до истечения.
    var requiresRefresh: Bool {
        Date() >= expiresAt.addingTimeInterval(-10)
    }

    func apply(to request: inout URLRequest) {
        request.headers.update(.authorization(bearerToken: accessToken))
    }

    func isApplied(to request: URLRequest) -> Bool {
        request.headers["Authorization"] == "Bearer \(accessToken)"
    }
}

/// Обновляет токен через `POST /auth/refresh`.
///
/// Запрос выполняется клиентом без авторизации, поэтому рекурсии нет.
struct SessionRefresher: CredentialRefresher {
    let publicClient: APIClient
    let lifetimeMinutes: Int

    func refresh(_ credential: SessionCredential) async throws -> SessionCredential {
        let tokens = try await publicClient.request(
            AuthRouter.refresh(
                RefreshRequest(refreshToken: credential.refreshToken, expiresInMins: lifetimeMinutes)
            ),
            as: TokenPair.self
        )

        return SessionCredential(tokens: tokens, lifetimeMinutes: lifetimeMinutes)
    }
}
