import Foundation
import Gatewire
import Testing

@Suite("Хранилища учётных данных")
struct CredentialStoreTests {
    @Test("Хранилище в памяти сохраняет, читает и удаляет")
    func inMemoryStore() async throws {
        let store = InMemoryCredentialStore<OAuth2Credential>()
        #expect(try await store.load() == nil)

        try await store.save(OAuth2Credential(accessToken: "access-1"))
        #expect(try await store.load()?.accessToken == "access-1")

        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test("Keychain сохраняет, перезаписывает, читает и удаляет")
    func keychainStore() async throws {
        let store = KeychainCredentialStore<OAuth2Credential>(
            service: "test.gatewire.\(UUID().uuidString)"
        )
        let credential = OAuth2Credential(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresAt: Date(timeIntervalSince1970: 1_000_000)
        )

        do {
            try await store.save(credential)
        } catch let error as KeychainError where error.status == errSecMissingEntitlement {
            // В тестовом окружении без подписи Keychain недоступен: проверять нечего.
            return
        }

        #expect(try await store.load() == credential)

        try await store.save(OAuth2Credential(accessToken: "access-2"))
        #expect(try await store.load()?.accessToken == "access-2")
        #expect(try await store.load()?.refreshToken == nil)

        try await store.clear()
        #expect(try await store.load() == nil)

        // Повторное удаление отсутствующего элемента не считается ошибкой.
        try await store.clear()
    }

    @Test("Разные аккаунты Keychain не мешают друг другу")
    func keychainAccountsAreIsolated() async throws {
        let service = "test.gatewire.\(UUID().uuidString)"
        let first = KeychainCredentialStore<OAuth2Credential>(service: service, account: "user-1")
        let second = KeychainCredentialStore<OAuth2Credential>(service: service, account: "user-2")

        do {
            try await first.save(OAuth2Credential(accessToken: "first"))
        } catch let error as KeychainError where error.status == errSecMissingEntitlement {
            return
        }
        try await second.save(OAuth2Credential(accessToken: "second"))

        #expect(try await first.load()?.accessToken == "first")
        #expect(try await second.load()?.accessToken == "second")

        try await first.clear()
        #expect(try await first.load() == nil)
        #expect(try await second.load()?.accessToken == "second")

        try await second.clear()
    }
}
