public import Foundation

/// Преобразует тело ответа с ошибкой в доменную ошибку конкретного API.
///
/// Вызывается, когда код ответа не входит в ``APIConfiguration/acceptableStatusCodes``.
///
/// ```swift
/// struct AppErrorMapper: APIErrorMapper {
///     func map(response: HTTPURLResponse, data: Data) -> (any Error)? {
///         try? JSONDecoder().decode(AppServerError.self, from: data)
///     }
/// }
/// ```
public protocol APIErrorMapper: Sendable {
    /// Возвращает доменную ошибку или `nil`, если тело ответа не распознано.
    ///
    /// Распознанная ошибка приходит как ``NetworkError/api(_:response:data:)``,
    /// нераспознанная — как ``NetworkError/unacceptableStatusCode(response:data:)``.
    func map(response: HTTPURLResponse, data: Data) -> (any Error)?
}
