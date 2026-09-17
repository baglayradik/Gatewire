/// Хранилище учётных данных между запусками приложения.
///
/// В пакете есть ``KeychainCredentialStore`` для постоянного хранения
/// и ``InMemoryCredentialStore`` для тестов.
public protocol CredentialStore<Credential>: Sendable {
    /// Тип учётных данных.
    associatedtype Credential: Sendable

    /// Возвращает сохранённые учётные данные или `nil`, если их нет.
    func load() async throws -> Credential?

    /// Сохраняет учётные данные.
    func save(_ credential: Credential) async throws

    /// Удаляет учётные данные.
    func clear() async throws
}

/// Хранилище в памяти: данные живут до завершения процесса.
public actor InMemoryCredentialStore<Credential: Sendable>: CredentialStore {
    private var credential: Credential?

    /// Создаёт хранилище.
    ///
    /// - Parameter credential: Начальные учётные данные. По умолчанию `nil`.
    public init(_ credential: Credential? = nil) {
        self.credential = credential
    }

    public func load() async throws -> Credential? {
        credential
    }

    public func save(_ credential: Credential) async throws {
        self.credential = credential
    }

    public func clear() async throws {
        credential = nil
    }
}
