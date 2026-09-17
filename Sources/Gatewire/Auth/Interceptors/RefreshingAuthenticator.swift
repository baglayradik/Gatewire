internal import Alamofire
internal import Foundation

/// Связывает ``CredentialRefresher`` и ``CredentialStore`` с `AuthenticationInterceptor` Alamofire.
///
/// Alamofire гарантирует, что при истёкшем или отклонённом токене обновление выполняется один раз:
/// остальные запросы ждут его результата и повторяются с новыми учётными данными.
final class RefreshingAuthenticator<Credential: RefreshableCredential>: Authenticator {
    private let refresher: any CredentialRefresher<Credential>
    private let store: any CredentialStore<Credential>
    private let refreshStatusCodes: Set<Int>
    private let scheme: AuthSchemeID
    private let events: AuthEventBroadcaster

    init(
        refresher: any CredentialRefresher<Credential>,
        store: any CredentialStore<Credential>,
        refreshStatusCodes: Set<Int>,
        scheme: AuthSchemeID,
        events: AuthEventBroadcaster
    ) {
        self.refresher = refresher
        self.store = store
        self.refreshStatusCodes = refreshStatusCodes
        self.scheme = scheme
        self.events = events
    }

    func apply(_ credential: Credential, to urlRequest: inout URLRequest) {
        credential.apply(to: &urlRequest)
    }

    func refresh(
        _ credential: Credential,
        for session: Session,
        completion: @escaping @Sendable (Result<Credential, any Error>) -> Void
    ) {
        Task { [refresher, store, scheme, events] in
            do {
                let refreshed = try await refresher.refresh(credential)

                do {
                    try await store.save(refreshed)
                } catch {
                    events.send(.storeFailed(scheme: scheme, error: error))
                }

                events.send(.refreshed(scheme: scheme))
                completion(.success(refreshed))
            } catch {
                events.send(.refreshFailed(scheme: scheme, error: error))
                completion(.failure(AuthenticationFailure.refreshFailed(error)))
            }
        }
    }

    func didRequest(
        _ urlRequest: URLRequest,
        with response: HTTPURLResponse,
        failDueToAuthenticationError error: any Error
    ) -> Bool {
        refreshStatusCodes.contains(response.statusCode)
    }

    func isRequest(_ urlRequest: URLRequest, authenticatedWith credential: Credential) -> Bool {
        credential.isApplied(to: urlRequest)
    }
}
