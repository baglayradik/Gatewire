import Foundation
import Gatewire
import Testing

@Suite("Package smoke tests")
struct PackageSmokeTests {
    @Test("Alamofire types are available through `import Gatewire`")
    func reexportedTypesAreAvailable() throws {
        let method: HTTPMethod = .post
        let headers: HTTPHeaders = [.contentType("application/json")]

        #expect(method.rawValue == "POST")
        #expect(headers.value(for: "Content-Type") == "application/json")
    }
}
