public import Alamofire
public import Foundation

/// Описание HTTP-запроса или группы запросов к API.
///
/// Обычно `Endpoint` реализуется перечислением-роутером: каждый `case` описывает отдельный запрос,
/// а свойства протокола через `switch` возвращают его параметры. Тип ответа в роутере не указывается —
/// он задаётся в месте вызова ``APIClient/request(_:as:)``.
///
/// ```swift
/// enum UserRouter: Endpoint {
///     case profile
///     case posts(userID: Int, page: Int)
///     case updateProfile(UpdateProfileRequest)
///
///     var baseURL: URL { URL(string: "https://api.example.com/v1")! }
///
///     var path: String {
///         switch self {
///         case .profile, .updateProfile: "me"
///         case .posts(let userID, _):    "users/\(userID)/posts"
///         }
///     }
///
///     var method: HTTPMethod {
///         switch self {
///         case .profile, .posts: .get
///         case .updateProfile:   .patch
///         }
///     }
///
///     var task: RequestTask {
///         switch self {
///         case .profile:                 .plain
///         case .posts(_, let page):      .query(["page": page])
///         case .updateProfile(let body): .json(body)
///         }
///     }
/// }
///
/// let profile = try await client.request(UserRouter.profile, as: UserDTO.self)
/// ```
///
/// `Endpoint` расширяет `URLRequestConvertible`, поэтому роутер можно передать и напрямую в Alamofire.
/// Реализация ``asURLRequest()`` по умолчанию собирает запрос из свойств протокола; при необходимости
/// её можно полностью переопределить.
///
/// Чтобы не повторять общие параметры в каждом роутере, объявите в проекте свой протокол
/// и задайте их один раз в его расширении:
///
/// ```swift
/// protocol AppEndpoint: Endpoint {}
///
/// extension AppEndpoint {
///     var baseURL: URL { AppConfig.apiBaseURL }
///     var jsonEncoder: JSONEncoder { .snakeCaseISO8601 }
/// }
/// ```
public protocol Endpoint: URLRequestConvertible, Sendable {
    /// Базовый адрес API, к которому добавляется ``path``.
    var baseURL: URL { get }

    /// Путь относительно ``baseURL``, например `"users/42/posts"`.
    ///
    /// Ведущий `/` необязателен. Параметры запроса передавайте через ``task``, а не в строке пути.
    var path: String { get }

    /// HTTP-метод. По умолчанию `.get`.
    var method: HTTPMethod { get }

    /// Параметры и тело запроса. По умолчанию ``RequestTask/plain``.
    var task: RequestTask { get }

    /// Заголовки запроса. По умолчанию пустые.
    ///
    /// Имеют приоритет над ``APIConfiguration/defaultHeaders``.
    var headers: HTTPHeaders { get }

    /// Нужны ли запросу учётные данные. По умолчанию ``AuthorizationRequirement/inherit``,
    /// то есть требование берётся из ``APIConfiguration/defaultAuthorization``.
    ///
    /// ```swift
    /// var authorization: AuthorizationRequirement {
    ///     switch self {
    ///     case .signIn, .refresh: .none
    ///     case .signOut:          .required
    ///     }
    /// }
    /// ```
    var authorization: AuthorizationRequirement { get }

    /// Таймаут запроса в секундах. По умолчанию `nil` — используется ``APIConfiguration/timeout``.
    ///
    /// ``APIClient`` всегда выставляет таймаут по этому свойству, поэтому задавайте его здесь,
    /// а не внутри собственной реализации ``asURLRequest()``.
    var timeoutInterval: TimeInterval? { get }

    /// Кодировщик тел ``RequestTask/json(_:)`` и ``RequestTask/queryAndJSON(query:body:)``.
    /// По умолчанию `JSONEncoder()`.
    var jsonEncoder: JSONEncoder { get }

    /// Кодировщик параметров ``RequestTask/query(_:)``, ``RequestTask/form(_:)``
    /// и строки запроса в ``RequestTask/queryAndJSON(query:body:)``. По умолчанию `URLEncodedFormEncoder()`.
    ///
    /// Настройте его, если API ожидает другой формат массивов, булевых значений или пробелов:
    ///
    /// ```swift
    /// var formEncoder: URLEncodedFormEncoder {
    ///     URLEncodedFormEncoder(arrayEncoding: .noBrackets, boolEncoding: .literal)
    /// }
    /// ```
    ///
    /// Возвращайте новый экземпляр при каждом обращении: `URLEncodedFormEncoder` не является `Sendable`.
    var formEncoder: URLEncodedFormEncoder { get }

    /// Декодер ответов для этого эндпоинта. По умолчанию `nil` — используется ``APIConfiguration/decoder``.
    var decoder: (any DataDecoder)? { get }
}

extension Endpoint {
    public var method: HTTPMethod { .get }
    public var task: RequestTask { .plain }
    public var headers: HTTPHeaders { [:] }
    public var authorization: AuthorizationRequirement { .inherit }
    public var timeoutInterval: TimeInterval? { nil }
    public var jsonEncoder: JSONEncoder { JSONEncoder() }
    public var formEncoder: URLEncodedFormEncoder { URLEncodedFormEncoder() }
    public var decoder: (any DataDecoder)? { nil }

    /// Собирает `URLRequest` из ``baseURL``, ``path``, ``method``, ``headers``, ``timeoutInterval`` и ``task``.
    ///
    /// - Throws: ``NetworkError/encodingFailed(_:)``, если не удалось закодировать параметры или тело.
    public func asURLRequest() throws -> URLRequest {
        var request = try URLRequest(url: Self.url(baseURL: baseURL, path: path), method: method, headers: headers)
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        return try task.encode(into: request, jsonEncoder: jsonEncoder, formEncoder: formEncoder)
    }

    static func url(baseURL: URL, path: String) -> URL {
        let relativePath = path.drop { $0 == "/" }
        guard !relativePath.isEmpty else { return baseURL }
        return baseURL.appendingPathComponent(String(relativePath))
    }
}
