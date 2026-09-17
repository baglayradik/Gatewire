/// Идентификатор схемы авторизации.
///
/// Если в приложении одна схема, используется ``default``. Несколько схем нужны, когда клиент
/// работает с разными видами учётных данных, например пользовательским токеном и ключом платёжного API.
///
/// ```swift
/// extension AuthSchemeID {
///     static let payments = AuthSchemeID("payments")
/// }
///
/// var authorization: AuthorizationRequirement { .required(.payments) }
/// ```
public struct AuthSchemeID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// Название схемы.
    public let rawValue: String

    /// Схема по умолчанию, настраиваемая через ``APIConfiguration/auth``.
    public static let `default` = AuthSchemeID("default")

    /// Создаёт идентификатор схемы.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public var description: String { rawValue }
}
