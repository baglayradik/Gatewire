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

    /// Преобразователь тел ответов с ошибкой в доменные ошибки API. По умолчанию `nil`.
    public var errorMapper: (any APIErrorMapper)?

    /// Таймаут запросов в секундах для эндпоинтов без ``Endpoint/timeoutInterval``. По умолчанию 30.
    public var timeout: TimeInterval = 30

    /// Коды ответа, которые считаются успешными. По умолчанию `200..<300`.
    public var acceptableStatusCodes: Range<Int> = 200..<300

    /// Фабрика конфигурации `URLSession`. По умолчанию `URLSessionConfiguration.default`.
    ///
    /// Используйте, чтобы настроить кеширование, прокси или подменить протоколы в тестах.
    public var sessionConfiguration: @Sendable () -> URLSessionConfiguration = { .default }

    /// Создаёт конфигурацию со значениями по умолчанию.
    public init() {}
}
