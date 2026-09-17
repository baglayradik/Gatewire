public import Foundation
internal import Security

/// Хранилище учётных данных в Keychain.
///
/// Данные сохраняются как элемент `kSecClassGenericPassword` в формате JSON.
///
/// ```swift
/// let store = KeychainCredentialStore<OAuth2Credential>(service: "com.company.app.auth")
/// ```
public struct KeychainCredentialStore<Credential: Codable & Sendable>: CredentialStore {
    /// Когда элемент Keychain доступен приложению.
    public enum Accessibility: Sendable {
        /// После первой разблокировки устройства, без переноса на другие устройства. Значение по умолчанию.
        case afterFirstUnlockThisDeviceOnly
        /// После первой разблокировки устройства, с переносом в резервные копии.
        case afterFirstUnlock
        /// Только когда устройство разблокировано, без переноса на другие устройства.
        case whenUnlockedThisDeviceOnly
        /// Только когда устройство разблокировано, с переносом в резервные копии.
        case whenUnlocked

        var secAttribute: CFString {
            switch self {
            case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
            case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
            }
        }
    }

    /// Имя сервиса элемента Keychain, обычно идентификатор приложения.
    public let service: String

    /// Имя аккаунта элемента Keychain.
    public let account: String

    /// Группа доступа для общего Keychain между приложениями. По умолчанию `nil`.
    public let accessGroup: String?

    /// Доступность элемента.
    public let accessibility: Accessibility

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Создаёт хранилище.
    ///
    /// - Parameters:
    ///   - service: Имя сервиса, обычно идентификатор приложения.
    ///   - account: Имя аккаунта. По умолчанию `"credential"`.
    ///   - accessGroup: Группа доступа общего Keychain. По умолчанию `nil`.
    ///   - accessibility: Доступность элемента. По умолчанию ``Accessibility/afterFirstUnlockThisDeviceOnly``.
    ///   - encoder: Кодировщик учётных данных. По умолчанию `JSONEncoder()`.
    ///   - decoder: Декодер учётных данных. По умолчанию `JSONDecoder()`.
    public init(
        service: String,
        account: String = "credential",
        accessGroup: String? = nil,
        accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.accessibility = accessibility
        self.encoder = encoder
        self.decoder = decoder
    }

    public func load() async throws -> Credential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }

            return try decoder.decode(Credential.self, from: data)

        case errSecItemNotFound:
            return nil

        default:
            throw KeychainError(status: status)
        }
    }

    public func save(_ credential: Credential) async throws {
        let data = try encoder.encode(credential)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus)
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility.secAttribute

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus)
        }
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

/// Ошибка обращения к Keychain.
public struct KeychainError: Error, CustomStringConvertible {
    /// Код ошибки Keychain.
    public let status: OSStatus

    /// Создаёт ошибку.
    public init(status: OSStatus) {
        self.status = status
    }

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "неизвестная ошибка"
        return "Ошибка Keychain \(status): \(message)"
    }
}
