internal import Alamofire
public import Foundation

/// Обновляет ``OAuth2Credential`` через token endpoint по RFC 6749, раздел 6.
///
/// Запрос обновления выполняется отдельной сессией без авторизации, поэтому рекурсия невозможна.
public struct OAuth2TokenRefresher: CredentialRefresher {
    /// Как передаётся секрет клиента.
    public enum ClientAuthentication: Sendable {
        /// В теле запроса параметром `client_secret`.
        case requestBody
        /// Заголовком `Authorization: Basic`.
        case basicHeader
    }

    /// Адрес token endpoint.
    public let tokenURL: URL

    /// Идентификатор клиента.
    public let clientID: String

    /// Секрет клиента для конфиденциальных клиентов. Для мобильных приложений обычно `nil`.
    public let clientSecret: String?

    /// Способ передачи секрета клиента.
    public let clientAuthentication: ClientAuthentication

    /// Дополнительные параметры тела запроса, например `scope`.
    public let additionalParameters: [String: String]

    /// Запас времени до истечения токена для новых учётных данных.
    public let refreshLeeway: TimeInterval

    private let session: Session

    /// Создаёт обновление токена.
    ///
    /// - Parameters:
    ///   - tokenURL: Адрес token endpoint.
    ///   - clientID: Идентификатор клиента.
    ///   - clientSecret: Секрет клиента. По умолчанию `nil`.
    ///   - clientAuthentication: Способ передачи секрета. По умолчанию ``ClientAuthentication/requestBody``.
    ///   - additionalParameters: Дополнительные параметры тела запроса. По умолчанию пусто.
    ///   - refreshLeeway: Запас времени до истечения токена. По умолчанию 60 секунд.
    ///   - sessionConfiguration: Фабрика конфигурации `URLSession` для запроса обновления.
    public init(
        tokenURL: URL,
        clientID: String,
        clientSecret: String? = nil,
        clientAuthentication: ClientAuthentication = .requestBody,
        additionalParameters: [String: String] = [:],
        refreshLeeway: TimeInterval = 60,
        sessionConfiguration: @Sendable () -> URLSessionConfiguration = { .default }
    ) {
        self.tokenURL = tokenURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.clientAuthentication = clientAuthentication
        self.additionalParameters = additionalParameters
        self.refreshLeeway = refreshLeeway
        self.session = Session(configuration: sessionConfiguration())
    }

    public func refresh(_ credential: OAuth2Credential) async throws -> OAuth2Credential {
        guard let refreshToken = credential.refreshToken else {
            throw OAuth2Error.missingRefreshToken
        }

        let request = try makeTokenRequest(refreshToken: refreshToken)
        let dataResponse = await session
            .request(request)
            .serializingResponse(using: RawDataSerializer())
            .response

        switch dataResponse.result {
        case let .success(data):
            guard let response = dataResponse.response else {
                throw NetworkError.transport(URLError(.badServerResponse))
            }
            return try makeCredential(data: data, response: response, previousRefreshToken: refreshToken)

        case let .failure(error):
            throw NetworkError(
                error,
                response: dataResponse.response,
                data: dataResponse.data,
                errorMapper: nil
            )
        }
    }

    private func makeTokenRequest(refreshToken: String) throws -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.method = .post

        var parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]

        switch clientAuthentication {
        case .basicHeader where clientSecret != nil:
            request.headers.update(.authorization(username: clientID, password: clientSecret ?? ""))

        case .basicHeader, .requestBody:
            parameters["client_id"] = clientID
            if let clientSecret {
                parameters["client_secret"] = clientSecret
            }
        }

        parameters.merge(additionalParameters) { _, new in new }

        do {
            return try URLEncodedFormParameterEncoder(destination: .httpBody)
                .encode(parameters, into: request)
        } catch {
            throw NetworkError.encodingFailed(error)
        }
    }

    private func makeCredential(
        data: Data,
        response: HTTPURLResponse,
        previousRefreshToken: String
    ) throws -> OAuth2Credential {
        let decoder = JSONDecoder()

        guard 200..<300 ~= response.statusCode else {
            if let serverError = try? decoder.decode(OAuth2ServerError.self, from: data) {
                throw OAuth2Error.server(
                    code: serverError.error,
                    description: serverError.errorDescription,
                    statusCode: response.statusCode
                )
            }
            throw OAuth2Error.unexpectedResponse(statusCode: response.statusCode)
        }

        do {
            let tokenResponse = try decoder.decode(OAuth2TokenResponse.self, from: data)
            return OAuth2Credential(
                tokenResponse,
                previousRefreshToken: previousRefreshToken,
                refreshLeeway: refreshLeeway
            )
        } catch {
            throw OAuth2Error.unexpectedResponse(statusCode: response.statusCode)
        }
    }
}

private struct OAuth2ServerError: Decodable {
    let error: String
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
