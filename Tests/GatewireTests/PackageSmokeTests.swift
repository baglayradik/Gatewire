import Foundation
import Gatewire
import Testing

@Suite("Smoke-тесты пакета")
struct PackageSmokeTests {
    @Test("Типы Alamofire доступны через `import Gatewire`")
    func reexportedTypesAreAvailable() throws {
        let method: HTTPMethod = .post
        let headers: HTTPHeaders = [.contentType("application/json")]

        #expect(method.rawValue == "POST")
        #expect(headers.value(for: "Content-Type") == "application/json")
    }

    @Test("Клиент создаётся без параметров и через замыкание настройки")
    func clientInitializers() {
        let defaultClient = APIClient()
        let configuredClient = APIClient { $0.timeout = 10 }

        #expect(defaultClient.configuration.timeout == 30)
        #expect(defaultClient.configuration.acceptableStatusCodes == 200..<300)
        #expect(configuredClient.configuration.timeout == 10)
    }
}
