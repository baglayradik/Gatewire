internal import Foundation

/// Перехватывает запросы сессий, созданных ``StubNetwork``, и отвечает заглушками.
///
/// Сеть определяется по служебному заголовку, который добавляет конфигурация сессии, поэтому
/// разные ``StubNetwork`` не мешают друг другу даже при одинаковых адресах запросов.
final class StubURLProtocol: URLProtocol {
    static let networkHeader = "X-Gatewire-Stub-Network"

    private final class WeakNetwork: Sendable {
        nonisolated(unsafe) weak var network: StubNetwork?

        init(_ network: StubNetwork) {
            self.network = network
        }
    }

    private static let networks = LockedValue<[String: WeakNetwork]>([:])

    // startLoading и stopLoading вызываются URLSession на одном потоке.
    private var loadingTask: Task<Void, Never>?

    static func register(_ network: StubNetwork) {
        networks.withValue { $0[network.id] = WeakNetwork(network) }
    }

    static func unregister(id: String) {
        networks.withValue { $0[id] = nil }
    }

    private static func network(for request: URLRequest) -> StubNetwork? {
        guard let id = request.value(forHTTPHeaderField: networkHeader) else { return nil }

        return networks.withValue { $0[id]?.network }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        network(for: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let network = Self.network(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let request = request
        let recordedRequest = request.recorded()
        // URLProtocol и его client не помечены как Sendable, но URLSession допускает
        // вызовы client с другого потока.
        nonisolated(unsafe) let urlProtocol = self

        loadingTask = Task {
            do {
                let stub = try await network.response(for: recordedRequest)

                if stub.delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(stub.delay * 1_000_000_000))
                }
                try Task.checkCancellation()

                if let failure = stub.failure {
                    urlProtocol.client?.urlProtocol(urlProtocol, didFailWithError: failure)
                    return
                }

                guard let url = request.url,
                      let response = HTTPURLResponse(
                          url: url,
                          statusCode: stub.statusCode,
                          httpVersion: "HTTP/1.1",
                          headerFields: Self.headers(for: stub)
                      )
                else {
                    urlProtocol.client?.urlProtocol(urlProtocol, didFailWithError: URLError(.badServerResponse))
                    return
                }

                if let redirect = Self.redirectRequest(for: response, from: request) {
                    // URLSession спросит обработчик перенаправлений. Если он откажется следовать
                    // за перенаправлением, задача должна завершиться исходным ответом 3xx,
                    // поэтому ответ отдаётся в любом случае.
                    urlProtocol.client?.urlProtocol(urlProtocol, wasRedirectedTo: redirect, redirectResponse: response)
                }

                urlProtocol.client?.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
                urlProtocol.client?.urlProtocol(urlProtocol, didLoad: stub.body)
                urlProtocol.client?.urlProtocolDidFinishLoading(urlProtocol)
            } catch is CancellationError {
                // Запрос отменён через stopLoading — URLSession уже знает об этом.
            } catch {
                urlProtocol.client?.urlProtocol(urlProtocol, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }

    private static func headers(for stub: StubResponse) -> [String: String] {
        var headers = stub.headers
        let hasContentLength = headers.keys.contains { $0.lowercased() == "content-length" }
        if hasContentLength == false {
            headers["Content-Length"] = "\(stub.body.count)"
        }
        return headers
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
        redirect.url = url.absoluteURL
        // Для 301, 302 и 303 клиенты меняют метод на GET, 307 и 308 сохраняют его.
        if [301, 302, 303].contains(response.statusCode), ["GET", "HEAD"].contains(request.httpMethod) == false {
            redirect.httpMethod = "GET"
            redirect.httpBody = nil
            redirect.httpBodyStream = nil
        }

        return redirect
    }
}

extension URLRequest {
    /// Копия запроса для записи: тело перенесено из потока в `httpBody`, служебный заголовок убран.
    fileprivate func recorded() -> URLRequest {
        var request = self
        request.setValue(nil, forHTTPHeaderField: StubURLProtocol.networkHeader)

        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }

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

        request.httpBodyStream = nil
        request.httpBody = body
        return request
    }
}
