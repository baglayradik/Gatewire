public import Foundation
public import Gatewire

/// Обновление учётных данных для тестов: возвращает заданные результаты и считает вызовы.
///
/// ```swift
/// let refresher = StubCredentialRefresher(returning: OAuth2Credential(accessToken: "new"))
/// let client = network.makeClient {
///     $0.auth = .refreshable(store: InMemoryCredentialStore(expiredCredential), refresher: refresher)
/// }
///
/// try await client.send(UserRouter.profile)
/// #expect(await refresher.refreshCount == 1)
/// ```
public actor StubCredentialRefresher<Credential: RefreshableCredential>: CredentialRefresher {
    /// Сколько раз вызывалось обновление.
    public private(set) var refreshCount = 0

    /// Учётные данные, переданные в последний вызов обновления.
    public private(set) var lastRefreshedCredential: Credential?

    private var results: [Result<Credential, any Error>]
    private let delay: TimeInterval

    /// Создаёт обновление, которое возвращает результаты по очереди; последний повторяется.
    ///
    /// - Parameters:
    ///   - results: Результаты обновления.
    ///   - delay: Задержка перед результатом в секундах. По умолчанию 0.
    public init(results: [Result<Credential, any Error>], delay: TimeInterval = 0) {
        precondition(results.isEmpty == false, "Нужен хотя бы один результат обновления.")

        self.results = results
        self.delay = delay
    }

    /// Создаёт обновление, которое всегда возвращает указанные учётные данные.
    public init(returning credential: Credential, delay: TimeInterval = 0) {
        self.init(results: [.success(credential)], delay: delay)
    }

    /// Создаёт обновление, которое всегда завершается указанной ошибкой.
    public init(failingWith error: any Error, delay: TimeInterval = 0) {
        self.init(results: [.failure(error)], delay: delay)
    }

    public func refresh(_ credential: Credential) async throws -> Credential {
        refreshCount += 1
        lastRefreshedCredential = credential

        let result = results.count > 1 ? results.removeFirst() : results[0]

        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        return try result.get()
    }
}
