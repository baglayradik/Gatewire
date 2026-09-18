internal import Alamofire
internal import Foundation

/// Пишет в лог запросы и ответы, маскируя секреты.
struct NetworkLogger: EventMonitor, Sendable {
    let queue = DispatchQueue(label: "Gatewire.logger")

    private let configuration: LoggingConfiguration
    private let redactor: SecretRedactor

    init(configuration: LoggingConfiguration) {
        self.configuration = configuration
        self.redactor = SecretRedactor(configuration: configuration)
    }

    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        var lines = ["→ \(urlRequest.method?.rawValue ?? "?") \(redactor.url(urlRequest.url))"]

        if configuration.level >= .headers, let headers = urlRequest.allHTTPHeaderFields, headers.isEmpty == false {
            lines.append(redactor.headers(headers))
        }
        if configuration.level >= .verbose,
           let body = redactor.body(
               urlRequest.httpBody,
               contentType: urlRequest.value(forHTTPHeaderField: "Content-Type")
           ) {
            lines.append(body)
        }

        configuration.sink(lines.joined(separator: "\n"))
    }

    func request(_ request: Request, didFailToCreateURLRequestWithError error: AFError) {
        configuration.sink("✗ не удалось собрать запрос: \(error.localizedDescription)")
    }

    func request<Value: Sendable>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
        let method = request.request?.method?.rawValue ?? "?"
        let url = redactor.url(request.request?.url)
        let duration = response.metrics?.taskInterval.duration

        var lines: [String] = []

        if let statusCode = response.response?.statusCode {
            let marker = 200..<300 ~= statusCode ? "←" : "✗"
            lines.append("\(marker) \(statusCode) \(method) \(url)\(durationSuffix(duration))")
        } else {
            let message = response.error?.localizedDescription ?? "нет ответа"
            lines.append("✗ \(method) \(url)\(durationSuffix(duration)): \(message)")
        }

        if configuration.level >= .headers, let headers = response.response?.allHeaderFields as? [String: String] {
            lines.append(redactor.headers(headers))
        }
        if configuration.level >= .verbose,
           let body = redactor.body(
               response.data,
               contentType: response.response?.value(forHTTPHeaderField: "Content-Type")
           ) {
            lines.append(body)
        }

        configuration.sink(lines.joined(separator: "\n"))
    }

    private func durationSuffix(_ duration: TimeInterval?) -> String {
        guard let duration else { return "" }

        return String(format: " (%.0f мс)", duration * 1000)
    }
}
