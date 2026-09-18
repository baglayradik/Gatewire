internal import Foundation

/// Маскирует секреты в адресах, заголовках и телах запросов.
struct SecretRedactor: Sendable {
    static let placeholder = "<скрыто>"

    let redactedHeaders: Set<String>
    let redactedParameters: Set<String>
    let maxBodyBytes: Int

    init(configuration: LoggingConfiguration) {
        self.redactedHeaders = Set(configuration.redactedHeaders.map { $0.lowercased() })
        self.redactedParameters = Set(configuration.redactedParameters.map { $0.lowercased() })
        self.maxBodyBytes = configuration.maxBodyBytes
    }

    func headers(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key.lowercased() < $1.key.lowercased() }
            .map { name, value in
                let value = redactedHeaders.contains(name.lowercased()) ? Self.placeholder : value
                return "\(name): \(value)"
            }
            .joined(separator: "\n")
    }

    func url(_ url: URL?) -> String {
        guard let url else { return "—" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            return url.absoluteString
        }

        components.queryItems = queryItems.map { item in
            guard redactedParameters.contains(item.name.lowercased()) else { return item }

            return URLQueryItem(name: item.name, value: Self.placeholder)
        }

        return components.url?.absoluteString ?? url.absoluteString
    }

    func body(_ data: Data?, contentType: String?) -> String? {
        guard let data, data.isEmpty == false else { return nil }

        if let json = redactedJSON(data) {
            return truncated(json)
        }
        if contentType?.contains("x-www-form-urlencoded") == true,
           let form = redactedForm(data) {
            return truncated(form)
        }
        guard let text = String(data: data.prefix(maxBodyBytes), encoding: .utf8) else {
            return "<\(data.count) байт>"
        }

        return truncated(text, originalByteCount: data.count)
    }

    private func redactedJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }

        let redacted = redact(jsonObject: object)
        guard let output = try? JSONSerialization.data(
            withJSONObject: redacted,
            options: [.sortedKeys, .fragmentsAllowed]
        ) else {
            return nil
        }

        return String(decoding: output, as: UTF8.self)
    }

    private func redact(jsonObject: Any) -> Any {
        switch jsonObject {
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: Any]()) { result, element in
                if redactedParameters.contains(element.key.lowercased()) {
                    result[element.key] = Self.placeholder
                } else {
                    result[element.key] = redact(jsonObject: element.value)
                }
            }

        case let array as [Any]:
            return array.map { redact(jsonObject: $0) }

        default:
            return jsonObject
        }
    }

    private func redactedForm(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var components = URLComponents()
        components.percentEncodedQuery = text
        guard let queryItems = components.queryItems else { return nil }

        return queryItems
            .map { item in
                let value = redactedParameters.contains(item.name.lowercased())
                    ? Self.placeholder
                    : (item.value ?? "")
                return "\(item.name)=\(value)"
            }
            .joined(separator: "&")
    }

    private func truncated(_ text: String, originalByteCount: Int? = nil) -> String {
        let byteCount = originalByteCount ?? text.utf8.count
        guard byteCount > maxBodyBytes else { return text }

        let prefix = String(decoding: Data(text.utf8).prefix(maxBodyBytes), as: UTF8.self)
        return "\(prefix)… (обрезано, всего \(byteCount) байт)"
    }
}
