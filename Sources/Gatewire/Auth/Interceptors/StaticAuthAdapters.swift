internal import Alamofire
internal import Foundation

/// Ошибка авторизации запроса.
enum AuthenticationFailure: Error {
    /// Учётных данных нет, а запрос их требует.
    case missingCredential

    /// Обновить учётные данные не удалось.
    case refreshFailed(any Error)
}

/// Добавляет заголовок `Authorization: Bearer` с токеном из внешнего источника.
struct BearerTokenAdapter: RequestInterceptor {
    let isOptional: Bool
    let token: @Sendable () async -> String?

    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        Task {
            guard let token = await token() else {
                completion(isOptional ? .success(urlRequest) : .failure(AuthenticationFailure.missingCredential))
                return
            }

            var request = urlRequest
            request.headers.update(.authorization(bearerToken: token))
            completion(.success(request))
        }
    }
}

/// Добавляет ключ API в заголовок или в строку запроса.
struct APIKeyAdapter: RequestInterceptor {
    let name: String
    let key: String
    let location: APIKeyLocation

    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        var request = urlRequest

        switch location {
        case .header:
            request.headers.update(name: name, value: key)
            completion(.success(request))

        case .queryParameter:
            guard let url = request.url,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                completion(.failure(AFError.invalidURL(url: urlRequest.url?.absoluteString ?? "")))
                return
            }

            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: name, value: key)]
            guard let urlWithKey = components.url else {
                completion(.failure(AFError.invalidURL(url: url.absoluteString)))
                return
            }

            request.url = urlWithKey
            completion(.success(request))
        }
    }
}

/// Добавляет заголовок `Authorization: Basic`.
struct BasicAuthAdapter: RequestInterceptor {
    let username: String
    let password: String

    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        var request = urlRequest
        request.headers.update(.authorization(username: username, password: password))
        completion(.success(request))
    }
}

/// Применяет авторизацию, только если учётные данные есть.
struct OptionalAuthenticationInterceptor<AuthenticatorType: Authenticator>: RequestInterceptor {
    let base: AuthenticationInterceptor<AuthenticatorType>

    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        guard base.credential != nil else {
            completion(.success(urlRequest))
            return
        }

        base.adapt(urlRequest, for: session, completion: completion)
    }

    func retry(
        _ request: Request,
        for session: Session,
        dueTo error: any Error,
        completion: @escaping @Sendable (RetryResult) -> Void
    ) {
        guard base.credential != nil else {
            completion(.doNotRetry)
            return
        }

        base.retry(request, for: session, dueTo: error, completion: completion)
    }
}
