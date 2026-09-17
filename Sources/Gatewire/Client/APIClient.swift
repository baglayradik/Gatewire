internal import Alamofire
public import Foundation

/// Клиент для выполнения запросов, описанных через ``Endpoint``.
///
/// Создайте один экземпляр на API и переиспользуйте его: клиент хранит `URLSession` с пулом соединений.
/// Все методы можно вызывать из любого контекста; отмена задачи отменяет и сетевой запрос.
///
/// ```swift
/// let client = APIClient {
///     $0.decoder = JSONDecoder.snakeCaseISO8601
/// }
///
/// let profile = try await client.request(UserRouter.profile, as: UserDTO.self)
/// let posts: [PostDTO] = try await client.request(UserRouter.posts(userID: 42, page: 1))
/// try await client.send(UserRouter.logout)
/// ```
public final class APIClient: Sendable {
    /// Настройки клиента.
    public let configuration: APIConfiguration

    let session: Session

    /// Создаёт клиент с указанными настройками.
    ///
    /// - Parameter configuration: Настройки клиента. По умолчанию — значения по умолчанию ``APIConfiguration``.
    public init(configuration: APIConfiguration = APIConfiguration()) {
        self.configuration = configuration
        self.session = Session(configuration: configuration.sessionConfiguration())
    }

    /// Создаёт клиент, изменяя настройки по умолчанию в замыкании.
    ///
    /// ```swift
    /// let client = APIClient {
    ///     $0.timeout = 15
    ///     $0.errorMapper = AppErrorMapper()
    /// }
    /// ```
    public convenience init(_ configure: (inout APIConfiguration) -> Void) {
        var configuration = APIConfiguration()
        configure(&configuration)
        self.init(configuration: configuration)
    }

    // MARK: - Запросы

    /// Выполняет запрос и декодирует `Decodable`-ответ.
    ///
    /// Используется ``Endpoint/decoder``, а если он не задан — ``APIConfiguration/decoder``.
    /// Тип ответа можно передать явно или вывести из контекста:
    ///
    /// ```swift
    /// let user = try await client.request(UserRouter.profile, as: UserDTO.self)
    /// let posts: [PostDTO] = try await client.request(UserRouter.posts(userID: 42, page: 1))
    /// ```
    public func request<Value: Decodable & Sendable>(
        _ endpoint: some Endpoint,
        as type: Value.Type = Value.self
    ) async throws(NetworkError) -> Value {
        try await response(endpoint, as: type).value
    }

    /// Выполняет запрос и декодирует ответ указанным декодером.
    ///
    /// ```swift
    /// let text = try await client.request(PageRouter.robots, decoder: .string)
    /// ```
    public func request<Decoder: ResponseDecoder>(
        _ endpoint: some Endpoint,
        decoder: Decoder
    ) async throws(NetworkError) -> Decoder.Output {
        try await response(endpoint, decoder: decoder).value
    }

    /// Выполняет запрос и возвращает декодированное значение вместе с HTTP-ответом.
    public func response<Value: Decodable & Sendable>(
        _ endpoint: some Endpoint,
        as type: Value.Type = Value.self
    ) async throws(NetworkError) -> APIResponse<Value> {
        let decoder = DecodableResponseDecoder<Value>(
            decoder: endpoint.decoder ?? configuration.decoder
        )
        return try await response(endpoint, decoder: decoder)
    }

    /// Выполняет запрос, декодирует ответ указанным декодером и возвращает значение вместе с HTTP-ответом.
    public func response<Decoder: ResponseDecoder>(
        _ endpoint: some Endpoint,
        decoder: Decoder
    ) async throws(NetworkError) -> APIResponse<Decoder.Output> {
        let (data, response) = try await perform(endpoint)
        do {
            let value = try decoder.decode(data, response: response)
            return APIResponse(value: value, response: response, data: data)
        } catch {
            throw .decodingFailed(error, data: data)
        }
    }

    /// Выполняет запрос без разбора тела ответа — проверяется только код ответа.
    public func send(_ endpoint: some Endpoint) async throws(NetworkError) {
        _ = try await perform(endpoint)
    }

    /// Выполняет запрос и возвращает тело ответа без декодирования.
    public func data(_ endpoint: some Endpoint) async throws(NetworkError) -> Data {
        try await perform(endpoint).data
    }

    // MARK: - Выполнение

    func perform(
        _ endpoint: some Endpoint
    ) async throws(NetworkError) -> (data: Data, response: HTTPURLResponse) {
        guard Task.isCancelled == false else { throw .cancelled }

        let urlRequest = try makeURLRequest(for: endpoint)
        let request: DataRequest = switch endpoint.task {
        case let .multipart(buildFormData):
            session.upload(multipartFormData: buildFormData, with: urlRequest)
        default:
            session.request(urlRequest)
        }

        let dataResponse = await request
            .validate(statusCode: configuration.acceptableStatusCodes)
            .serializingResponse(using: RawDataSerializer())
            .response

        switch dataResponse.result {
        case let .success(data):
            guard let response = dataResponse.response else {
                throw .transport(URLError(.badServerResponse))
            }
            return (data, response)
       
        case let .failure(error):
            throw NetworkError(
                error,
                response: dataResponse.response,
                data: dataResponse.data,
                errorMapper: configuration.errorMapper
            )
        }
    }

    func makeURLRequest(for endpoint: some Endpoint) throws(NetworkError) -> URLRequest {
        var request: URLRequest
        do {
            request = try endpoint.asURLRequest()
        } catch {
            let networkError = NetworkError(error, response: nil, data: nil, errorMapper: nil)
            if case .underlying = networkError {
                throw .invalidRequest(error)
            }
            throw networkError
        }

        for header in configuration.defaultHeaders
        where request.value(forHTTPHeaderField: header.name) == nil
        {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        request.timeoutInterval = endpoint.timeoutInterval ?? configuration.timeout
        return request
    }
}

/// Возвращает тело ответа как есть; пустой ответ — пустые данные, а не ошибка.
private struct RawDataSerializer: DataResponseSerializerProtocol {
    func serialize(
        request: URLRequest?,
        response: HTTPURLResponse?,
        data: Data?,
        error: (any Error)?
    ) throws -> Data {
        if let error {
            throw error
        }
        return data ?? Data()
    }
}
