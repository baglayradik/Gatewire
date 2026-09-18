public import Alamofire
public import Foundation

/// Настройки ``APIClient``.
///
/// У всех параметров есть значения по умолчанию, поэтому задавать нужно только отличающиеся:
///
/// ```swift
/// let client = APIClient {
///     $0.decoder = JSONDecoder.snakeCaseISO8601
///     $0.errorMapper = AppErrorMapper()
/// }
/// ```
public struct APIConfiguration: Sendable {
    /// Заголовки, добавляемые ко всем запросам. По умолчанию `Accept-Encoding`, `Accept-Language` и `User-Agent`.
    ///
    /// Заголовки из ``Endpoint/headers`` с тем же именем имеют приоритет.
    public var defaultHeaders: HTTPHeaders = .default

    /// Декодер ответов для эндпоинтов, у которых ``Endpoint/decoder`` равен `nil`. По умолчанию `JSONDecoder()`.
    public var decoder: any DataDecoder = JSONDecoder()

    /// Стратегия авторизации схемы ``AuthSchemeID/default``. По умолчанию `nil` — запросы без авторизации.
    public var auth: AuthStrategy?

    /// Дополнительные схемы авторизации, если клиент работает с несколькими видами учётных данных.
    public var additionalAuth: [AuthSchemeID: AuthStrategy] = [:]

    /// Требование авторизации для эндпоинтов с ``AuthorizationRequirement/inherit``.
    ///
    /// По умолчанию ``AuthorizationRequirement/inherit``: это значит ``AuthorizationRequirement/required``,
    /// если задана ``auth`` или ``additionalAuth``, и ``AuthorizationRequirement/none``, если стратегий нет.
    public var defaultAuthorization: AuthorizationRequirement = .inherit

    /// Преобразователь тел ответов с ошибкой в доменные ошибки API. По умолчанию `nil`.
    public var errorMapper: (any APIErrorMapper)?

    /// Таймаут запросов в секундах для эндпоинтов без ``Endpoint/timeoutInterval``. По умолчанию 30.
    public var timeout: TimeInterval = 30

    /// Коды ответа, которые считаются успешными. По умолчанию `200..<300`.
    public var acceptableStatusCodes: Range<Int> = 200..<300

    /// Настройки повторов запросов. По умолчанию два повтора идемпотентных запросов.
    public var retry: RetryConfiguration = .default

    /// Настройки логирования. По умолчанию логирование выключено.
    public var logging: LoggingConfiguration = .disabled

    /// Проверка сертификата сервера. По умолчанию `nil` — системная проверка.
    public var serverTrust: ServerTrustConfiguration?

    /// Что делать с перенаправлениями.
    ///
    /// По умолчанию клиент следует за ними, но убирает `Authorization`, `Cookie` и другие
    /// чувствительные заголовки при переходе на другой хост.
    public var redirects: RedirectConfiguration = .followStrippingSensitiveHeaders

    /// Дополнительные мониторы событий Alamofire, например для метрик или своего логирования.
    public var eventMonitors: [any EventMonitor] = []

    /// Фабрика конфигурации `URLSession`. По умолчанию `URLSessionConfiguration.default`.
    ///
    /// Используйте, чтобы настроить кеширование, прокси или подменить протоколы в тестах.
    public var sessionConfiguration: @Sendable () -> URLSessionConfiguration = { .default }

    /// Создаёт конфигурацию со значениями по умолчанию.
    public init() {}
}
