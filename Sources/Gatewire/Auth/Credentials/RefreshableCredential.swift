public import Alamofire
public import Foundation

/// Учётные данные, которые подставляются в запрос и умеют обновляться.
///
/// Свойство `requiresRefresh` протокола `AuthenticationCredential` должно возвращать `true`,
/// когда токен истёк или истечёт в ближайшие секунды: тогда он обновится до отправки запроса.
///
/// ```swift
/// struct SessionCredential: RefreshableCredential {
///     let token: String
///     let expiresAt: Date
///
///     var requiresRefresh: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
///
///     func apply(to request: inout URLRequest) {
///         request.headers.update(.authorization(bearerToken: token))
///     }
///
///     func isApplied(to request: URLRequest) -> Bool {
///         request.headers["Authorization"] == "Bearer \(token)"
///     }
/// }
/// ```
public protocol RefreshableCredential: AuthenticationCredential, Codable, Sendable {
    /// Добавляет учётные данные в запрос.
    func apply(to request: inout URLRequest)

    /// Сообщает, отправлен ли запрос с этими учётными данными.
    ///
    /// Нужно, чтобы не обновлять токен повторно, когда его уже обновил другой запрос.
    func isApplied(to request: URLRequest) -> Bool
}

/// Обновляет учётные данные, когда они истекли или сервер их отклонил.
///
/// Реализация должна выполнять запрос обновления **без авторизации**, иначе возможна рекурсия.
/// Для OAuth 2.0 в пакете есть ``OAuth2TokenRefresher``.
public protocol CredentialRefresher<Credential>: Sendable {
    /// Тип учётных данных.
    associatedtype Credential: RefreshableCredential

    /// Возвращает новые учётные данные.
    ///
    /// Вызывается не более одного раза одновременно: остальные запросы ждут результата.
    /// Брошенная ошибка приходит как ``NetworkError/authenticationFailed(_:)``.
    func refresh(_ credential: Credential) async throws -> Credential
}
