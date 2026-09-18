public import Alamofire
internal import Foundation

/// Что делать с перенаправлениями.
public struct RedirectConfiguration: Sendable {
    let makeHandler: @Sendable () -> any RedirectHandler

    /// Следовать перенаправлениям, убирая чувствительные заголовки при переходе на другой хост.
    ///
    /// Значение по умолчанию. `URLSession` переносит заголовки запроса на новый адрес,
    /// поэтому без этой защиты токен мог бы уйти на посторонний хост.
    public static let followStrippingSensitiveHeaders = RedirectConfiguration {
        SensitiveHeaderRedirectHandler(sensitiveHeaders: SensitiveHeaderRedirectHandler.defaultSensitiveHeaders)
    }

    /// Следовать перенаправлениям, сохраняя все заголовки.
    public static let follow = RedirectConfiguration {
        Redirector(behavior: .follow)
    }

    /// Не следовать перенаправлениям: ответ 3xx возвращается как есть.
    public static let doNotFollow = RedirectConfiguration {
        Redirector(behavior: .doNotFollow)
    }

    /// Следовать перенаправлениям, убирая указанные заголовки при переходе на другой хост.
    ///
    /// - Parameter sensitiveHeaders: Имена заголовков. Регистр не важен.
    public static func followStripping(_ sensitiveHeaders: Set<String>) -> RedirectConfiguration {
        RedirectConfiguration {
            SensitiveHeaderRedirectHandler(sensitiveHeaders: sensitiveHeaders)
        }
    }

    /// Свой обработчик перенаправлений.
    public static func custom(_ handler: any RedirectHandler) -> RedirectConfiguration {
        RedirectConfiguration { handler }
    }
}

/// Убирает чувствительные заголовки при перенаправлении на другой хост.
struct SensitiveHeaderRedirectHandler: RedirectHandler {
    static let defaultSensitiveHeaders: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "x-api-key",
        "x-auth-token",
    ]

    let sensitiveHeaders: Set<String>

    func task(
        _ task: URLSessionTask,
        willBeRedirectedTo request: URLRequest,
        for response: HTTPURLResponse,
        completion: @escaping (URLRequest?) -> Void
    ) {
        let originalHost = task.originalRequest?.url?.host?.lowercased()
        let redirectHost = request.url?.host?.lowercased()

        guard originalHost != redirectHost else {
            completion(request)
            return
        }

        let sensitiveHeaders = Set(sensitiveHeaders.map { $0.lowercased() })
        var request = request
        for name in request.allHTTPHeaderFields?.keys ?? [:].keys
        where sensitiveHeaders.contains(name.lowercased()) {
            request.setValue(nil, forHTTPHeaderField: name)
        }

        completion(request)
    }
}
