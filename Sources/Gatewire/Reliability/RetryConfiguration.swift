public import Alamofire
public import Foundation

/// Настройки повторов запросов.
///
/// Повторяются только идемпотентные методы и только те ошибки, которые имеют смысл повторять:
/// таймауты, обрывы соединения и коды ответа вроде 503. Ответы 401 и 403 повторами не обрабатываются —
/// это задача авторизации (см. ``AuthStrategy``).
///
/// ```swift
/// let client = APIClient {
///     $0.retry.limit = 3
///     $0.retry.methods.insert(.post)  // если POST в вашем API идемпотентен
/// }
/// ```
public struct RetryConfiguration: Sendable {
    /// Сколько раз повторять запрос. `0` отключает повторы. По умолчанию 2.
    public var limit: UInt = 2

    /// HTTP-методы, которые можно повторять. По умолчанию идемпотентные.
    public var methods: Set<HTTPMethod> = [.get, .head, .options, .put, .delete, .trace]

    /// Коды ответа, при которых запрос повторяется. По умолчанию 408, 500, 502, 503 и 504.
    public var statusCodes: Set<Int> = [408, 500, 502, 503, 504]

    /// Ошибки сети, при которых запрос повторяется.
    public var urlErrorCodes: Set<URLError.Code> = [
        .backgroundSessionInUseByAnotherProcess,
        .backgroundSessionWasDisconnected,
        .cannotConnectToHost,
        .cannotFindHost,
        .cannotLoadFromNetwork,
        .dnsLookupFailed,
        .downloadDecodingFailedMidStream,
        .downloadDecodingFailedToComplete,
        .internationalRoamingOff,
        .networkConnectionLost,
        .notConnectedToInternet,
        .secureConnectionFailed,
        .serverCertificateHasBadDate,
        .serverCertificateNotYetValid,
        .timedOut,
    ]

    /// Основание экспоненциальной задержки между повторами. Минимум 2. По умолчанию 2.
    public var exponentialBackoffBase: UInt = 2

    /// Множитель задержки в секундах. По умолчанию 0.5, то есть задержки 1, 2, 4 секунды.
    public var exponentialBackoffScale: Double = 0.5

    /// Настройки по умолчанию: два повтора идемпотентных запросов.
    public static let `default` = RetryConfiguration()

    /// Повторы отключены.
    public static let disabled = RetryConfiguration(limit: 0)

    /// Создаёт настройки повторов.
    public init(limit: UInt = 2) {
        self.limit = limit
    }

    /// Интерцептор повторов или `nil`, если повторы отключены.
    func makeInterceptor() -> (any RequestInterceptor)? {
        guard limit > 0 else { return nil }

        return RetryPolicy(
            retryLimit: limit,
            exponentialBackoffBase: exponentialBackoffBase,
            exponentialBackoffScale: exponentialBackoffScale,
            retryableHTTPMethods: methods,
            retryableHTTPStatusCodes: statusCodes,
            retryableURLErrorCodes: urlErrorCodes
        )
    }
}
