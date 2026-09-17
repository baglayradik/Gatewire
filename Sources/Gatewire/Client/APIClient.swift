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
        try await response(endpoint, decoder: DecodableResponseDecoder<Value>())
    }

    /// Выполняет запрос, декодирует ответ указанным декодером и возвращает значение вместе с HTTP-ответом.
    public func response<Decoder: ResponseDecoder>(
        _ endpoint: some Endpoint,
        decoder: Decoder
    ) async throws(NetworkError) -> APIResponse<Decoder.Output> {
        try await decode(endpoint, decoder: decoder, uploadProgress: nil)
    }

    /// Выполняет запрос без разбора тела ответа — проверяется только код ответа.
    public func send(_ endpoint: some Endpoint) async throws(NetworkError) {
        _ = try await perform(endpoint)
    }

    /// Выполняет запрос и возвращает тело ответа без декодирования.
    public func data(_ endpoint: some Endpoint) async throws(NetworkError) -> Data {
        try await perform(endpoint).data
    }

    // MARK: - Загрузка и скачивание

    /// Отправляет тело запроса с отслеживанием прогресса и декодирует `Decodable`-ответ.
    ///
    /// Подходит для любого ``RequestTask`` с телом, чаще всего ``RequestTask/multipart(_:)``.
    ///
    /// ```swift
    /// let avatar = try await client.upload(UserRouter.uploadAvatar(jpegData), as: AvatarDTO.self) { progress in
    ///     self.uploadFraction = progress.fractionCompleted
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - endpoint: Эндпоинт запроса.
    ///   - type: Тип ответа.
    ///   - progress: Обработчик прогресса отправки, вызывается на главном потоке.
    public func upload<Value: Decodable & Sendable>(
        _ endpoint: some Endpoint,
        as type: Value.Type,
        progress: @escaping TransferProgressHandler
    ) async throws(NetworkError) -> Value {
        try await decode(endpoint, decoder: DecodableResponseDecoder<Value>(), uploadProgress: progress).value
    }

    /// Отправляет тело запроса с отслеживанием прогресса и декодирует ответ указанным декодером.
    ///
    /// - Parameters:
    ///   - endpoint: Эндпоинт запроса.
    ///   - decoder: Декодер ответа.
    ///   - progress: Обработчик прогресса отправки, вызывается на главном потоке.
    public func upload<Decoder: ResponseDecoder>(
        _ endpoint: some Endpoint,
        decoder: Decoder,
        progress: @escaping TransferProgressHandler
    ) async throws(NetworkError) -> Decoder.Output {
        try await decode(endpoint, decoder: decoder, uploadProgress: progress).value
    }

    /// Отправляет тело запроса с отслеживанием прогресса без разбора тела ответа.
    ///
    /// - Parameters:
    ///   - endpoint: Эндпоинт запроса.
    ///   - progress: Обработчик прогресса отправки, вызывается на главном потоке.
    public func upload(
        _ endpoint: some Endpoint,
        progress: @escaping TransferProgressHandler
    ) async throws(NetworkError) {
        _ = try await perform(endpoint, uploadProgress: progress)
    }

    /// Скачивает тело ответа в файл.
    ///
    /// Промежуточные папки создаются автоматически, существующий файл по адресу `destination` заменяется.
    /// Если сервер вернул недопустимый код ответа, скачанный файл удаляется, а его содержимое
    /// приходит в ошибке как тело ответа.
    ///
    /// ```swift
    /// let fileURL = try await client.download(
    ///     ReportRouter.pdf(id: 42),
    ///     to: .documentsDirectory.appending(path: "report-42.pdf")
    /// ) { progress in
    ///     self.downloadFraction = progress.fractionCompleted
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - endpoint: Эндпоинт запроса. ``RequestTask/multipart(_:)`` не поддерживается.
    ///   - destination: Адрес файла, в который сохраняется ответ.
    ///   - progress: Обработчик прогресса скачивания, вызывается на главном потоке.
    /// - Returns: Адрес сохранённого файла.
    @discardableResult
    public func download(
        _ endpoint: some Endpoint,
        to destination: URL,
        progress: TransferProgressHandler? = nil
    ) async throws(NetworkError) -> URL {
        guard Task.isCancelled == false else { throw .cancelled }

        if case .multipart = endpoint.task {
            throw .invalidRequest(UsageError("Скачивание в файл не поддерживает multipart-запросы."))
        }

        let urlRequest = try makeURLRequest(for: endpoint)
        let request = session.download(urlRequest) { _, _ in
            (destination, [.createIntermediateDirectories, .removePreviousFile])
        }
        if let progress {
            request.downloadProgress(queue: .main) { value in
                let transferProgress = TransferProgress(value)
                MainActor.assumeIsolated { progress(transferProgress) }
            }
        }

        let downloadResponse = await request
            .validate(statusCode: configuration.acceptableStatusCodes)
            .serializingDownloadedFileURL()
            .response

        switch downloadResponse.result {
        case let .success(fileURL):
            return fileURL

        case let .failure(error):
            // При недопустимом коде ответа в файл сохраняется тело ошибки: передаём его в ошибку
            // и не оставляем вместо ожидаемого файла.
            var errorData: Data?
            if let fileURL = downloadResponse.fileURL {
                errorData = try? Data(contentsOf: fileURL)
                try? FileManager.default.removeItem(at: fileURL)
            }
            throw NetworkError(
                error,
                response: downloadResponse.response,
                data: errorData,
                errorMapper: configuration.errorMapper
            )
        }
    }

    // MARK: - Выполнение

    func decode<Decoder: ResponseDecoder>(
        _ endpoint: some Endpoint,
        decoder: Decoder,
        uploadProgress: TransferProgressHandler?
    ) async throws(NetworkError) -> APIResponse<Decoder.Output> {
        let (data, response) = try await perform(endpoint, uploadProgress: uploadProgress)
        let context = ResponseDecodingContext(
            response: response,
            dataDecoder: endpoint.decoder ?? configuration.decoder
        )

        do {
            let value = try decoder.decode(data, context: context)
            return APIResponse(value: value, response: response, data: data)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw .decodingFailed(error, data: data)
        }
    }

    func perform(
        _ endpoint: some Endpoint,
        uploadProgress: TransferProgressHandler? = nil
    ) async throws(NetworkError) -> (data: Data, response: HTTPURLResponse) {
        guard Task.isCancelled == false else { throw .cancelled }

        let urlRequest = try makeURLRequest(for: endpoint)
        let request: DataRequest = switch endpoint.task {
        case let .multipart(buildFormData):
            session.upload(multipartFormData: buildFormData, with: urlRequest)
        default:
            session.request(urlRequest)
        }

        if let uploadProgress {
            request.uploadProgress(queue: .main) { value in
                let transferProgress = TransferProgress(value)
                MainActor.assumeIsolated { uploadProgress(transferProgress) }
            }
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

/// Ошибка неверного использования API клиента.
struct UsageError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
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
