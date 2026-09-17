internal import Alamofire
internal import Foundation

extension NetworkError {
    /// Преобразует ошибку Alamofire или любую другую ошибку выполнения запроса в `NetworkError`.
    init(
        _ error: any Error,
        response: HTTPURLResponse?,
        data: Data?,
        errorMapper: (any APIErrorMapper)?
    ) {
        if let networkError = error as? NetworkError {
            self = networkError
            return
        }
        if let urlError = error as? URLError {
            self = urlError.code == .cancelled ? .cancelled : .transport(urlError)
            return
        }
        guard let afError = error as? AFError else {
            self = .underlying(error)
            return
        }

        switch afError {
        case .explicitlyCancelled:
            self = .cancelled

        case .responseValidationFailed(reason: .unacceptableStatusCode):
            guard let response else {
                self = .underlying(afError)
                return
            }
            let data = data ?? Data()
            if let apiError = errorMapper?.map(response: response, data: data) {
                self = .api(apiError, response: response, data: data)
            } else {
                self = .unacceptableStatusCode(response: response, data: data)
            }

        case let .sessionTaskFailed(underlyingError),
             let .requestAdaptationFailed(underlyingError),
             let .requestRetryFailed(_, underlyingError):
            self = NetworkError(
                underlyingError,
                response: response,
                data: data,
                errorMapper: errorMapper
            )

        case let .createURLRequestFailed(underlyingError),
             let .createUploadableFailed(underlyingError):
            let mapped = NetworkError(
                underlyingError,
                response: response,
                data: data,
                errorMapper: errorMapper
            )
            if case .underlying = mapped {
                self = .invalidRequest(underlyingError)
            } else {
                self = mapped
            }

        case .parameterEncodingFailed, .parameterEncoderFailed, .multipartEncodingFailed:
            self = .encodingFailed(afError)

        case .invalidURL, .urlRequestValidationFailed:
            self = .invalidRequest(afError)

        default:
            self = .underlying(afError)
        }
    }
}
