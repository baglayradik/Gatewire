internal import Alamofire
internal import Foundation
internal import os

/// Настройки логирования запросов.
///
/// Секреты маскируются всегда: заголовки из ``redactedHeaders`` и параметры из ``redactedParameters``
/// заменяются на `<скрыто>` в адресах, заголовках и телах запросов и ответов.
///
/// ```swift
/// let client = APIClient {
///     #if DEBUG
///     $0.logging = .verbose
///     #endif
/// }
/// ```
public struct LoggingConfiguration: Sendable {
    /// Что попадает в лог.
    public enum Level: Int, Sendable, Comparable {
        /// Логирование выключено.
        case disabled
        /// Метод, адрес, код ответа и длительность.
        case basic
        /// То же плюс заголовки запроса и ответа.
        case headers
        /// То же плюс тела запроса и ответа.
        case verbose

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Уровень логирования. По умолчанию ``Level/disabled``.
    public var level: Level

    /// Заголовки, значения которых маскируются. Регистр не важен.
    public var redactedHeaders: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
    ]

    /// Имена параметров и полей JSON, значения которых маскируются. Регистр не важен.
    public var redactedParameters: Set<String> = [
        "access_token",
        "refresh_token",
        "id_token",
        "token",
        "code",
        "password",
        "secret",
        "client_secret",
        "api_key",
        "apikey",
    ]

    /// Максимальный размер тела в логе. Всё лишнее обрезается. По умолчанию 4 КБ.
    public var maxBodyBytes: Int = 4096

    /// Куда писать строки лога. По умолчанию в `os.Logger` подсистемы `Gatewire`.
    public var sink: @Sendable (String) -> Void = { message in
        Logger(subsystem: "Gatewire", category: "network").debug("\(message, privacy: .public)")
    }

    /// Логирование выключено.
    public static let disabled = LoggingConfiguration(level: .disabled)

    /// Метод, адрес, код ответа и длительность.
    public static let basic = LoggingConfiguration(level: .basic)

    /// То же, что ``basic``, плюс заголовки.
    public static let headers = LoggingConfiguration(level: .headers)

    /// То же, что ``headers``, плюс тела запроса и ответа.
    public static let verbose = LoggingConfiguration(level: .verbose)

    /// Создаёт настройки логирования.
    public init(level: Level = .disabled) {
        self.level = level
    }

    /// Монитор событий для сессии или `nil`, если логирование выключено.
    func makeEventMonitor() -> (any EventMonitor)? {
        guard level > .disabled else { return nil }

        return NetworkLogger(configuration: self)
    }
}
