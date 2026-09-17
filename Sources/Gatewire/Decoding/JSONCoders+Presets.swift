public import Foundation

extension JSONDecoder {
    /// Декодер для API в стиле `snake_case` с датами в ISO 8601.
    ///
    /// Каждый вызов создаёт новый экземпляр. Даты с долями секунд (`2026-09-18T10:00:00.123Z`)
    /// стратегия `.iso8601` не поддерживает — для них настройте `dateDecodingStrategy` самостоятельно.
    public static var snakeCaseISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    /// Кодировщик для API в стиле `snake_case` с датами в ISO 8601.
    ///
    /// Каждый вызов создаёт новый экземпляр.
    public static var snakeCaseISO8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
