internal import Alamofire
internal import Foundation

/// Возвращает тело ответа как есть; пустой ответ — пустые данные, а не ошибка.
struct RawDataSerializer: DataResponseSerializerProtocol {
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
