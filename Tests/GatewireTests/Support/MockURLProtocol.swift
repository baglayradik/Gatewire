import Alamofire
import Foundation

/// Подменяет сетевой слой `URLSession` в тестах.
///
/// Обработчики регистрируются по хосту, поэтому параллельно выполняющиеся тесты
/// с разными хостами не мешают друг другу.
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)

    private static let handlers = Locked<[String: Handler]>([:])

    // startLoading и stopLoading вызываются URLSession на одном потоке.
    private var loadingTask: Task<Void, Never>?

    static func register(host: String, handler: @escaping Handler) {
        handlers.withValue { $0[host] = handler }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return handlers.withValue { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host, let handler = Self.handlers.withValue({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let request = request.withBodyFromStream()
        // URLProtocol и его client не помечены как Sendable, но URLSession допускает
        // вызовы client с другого потока — в тестах это безопасно.
        nonisolated(unsafe) let urlProtocol = self
        loadingTask = Task {
            do {
                let (response, data) = try await handler(request)
                try Task.checkCancellation()

                if let redirect = Self.redirectRequest(for: response, from: request) {
                    // URLSession спросит обработчик перенаправлений. Если он откажется следовать
                    // за перенаправлением, задача должна завершиться исходным ответом 3xx,
                    // поэтому ответ отдаём в любом случае.
                    urlProtocol.client?.urlProtocol(urlProtocol, wasRedirectedTo: redirect, redirectResponse: response)
                }

                urlProtocol.client?.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
                urlProtocol.client?.urlProtocol(urlProtocol, didLoad: data)
                urlProtocol.client?.urlProtocolDidFinishLoading(urlProtocol)
            } catch is CancellationError {
                // Запрос отменён через stopLoading — URLSession уже знает об этом.
            } catch {
                urlProtocol.client?.urlProtocol(urlProtocol, didFailWithError: error)
            }
        }
    }

    /// Запрос перенаправления для ответа 3xx с заголовком `Location`.
    ///
    /// URLSession не строит такой запрос сам, когда ответ приходит из URLProtocol.
    private static func redirectRequest(for response: HTTPURLResponse, from request: URLRequest) -> URLRequest? {
        guard 300..<400 ~= response.statusCode,
              let location = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: request.url)
        else {
            return nil
        }

        var redirect = request
        redirect.url = url
        // 303 и большинство клиентов для 301/302 меняют метод на GET, 307 и 308 сохраняют его.
        if [301, 302, 303].contains(response.statusCode), request.method != .get, request.method != .head {
            redirect.method = .get
            redirect.httpBody = nil
        }

        return redirect
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}

extension URLRequest {
    /// URLSession передаёт тело в URLProtocol потоком — переносим его в `httpBody` для проверок в тестах.
    fileprivate func withBodyFromStream() -> URLRequest {
        guard httpBody == nil, let stream = httpBodyStream else { return self }

        var request = self
        var body = Data()
        let bufferSize = 16_384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        stream.open()
        defer { stream.close() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        request.httpBody = body
        return request
    }
}
