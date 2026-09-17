/// Нужны ли запросу учётные данные.
///
/// Задаётся в ``Endpoint/authorization``. Запросы с ``none`` никогда не получают токен,
/// даже если пользователь авторизован.
public struct AuthorizationRequirement: Sendable, Hashable {
    enum Mode: Sendable, Hashable {
        case inherit
        case none
        case required
        case optional
    }

    let mode: Mode
    let scheme: AuthSchemeID

    /// Взять требование из ``APIConfiguration/defaultAuthorization``.
    public static let inherit = AuthorizationRequirement(mode: .inherit, scheme: .default)

    /// Запрос без авторизации.
    public static let none = AuthorizationRequirement(mode: .none, scheme: .default)

    /// Запрос требует учётных данных схемы ``AuthSchemeID/default``.
    ///
    /// Если учётных данных нет, запрос не отправляется и приходит ``NetworkError/unauthenticated``.
    public static let required = AuthorizationRequirement(mode: .required, scheme: .default)

    /// Учётные данные схемы ``AuthSchemeID/default`` добавляются, только если они есть.
    public static let optional = AuthorizationRequirement(mode: .optional, scheme: .default)

    /// Запрос требует учётных данных указанной схемы.
    public static func required(_ scheme: AuthSchemeID) -> AuthorizationRequirement {
        AuthorizationRequirement(mode: .required, scheme: scheme)
    }

    /// Учётные данные указанной схемы добавляются, только если они есть.
    public static func optional(_ scheme: AuthSchemeID) -> AuthorizationRequirement {
        AuthorizationRequirement(mode: .optional, scheme: scheme)
    }

    /// Подставляет требование по умолчанию вместо ``inherit``.
    func resolved(default defaultRequirement: AuthorizationRequirement) -> AuthorizationRequirement {
        mode == .inherit ? defaultRequirement : self
    }
}
