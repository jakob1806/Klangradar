import Foundation
import Security

struct KeychainStore: Sendable {
    private let service = "de.klangradar.native"
    /// Nur für Tests: Der Test-Host ohne Code-Signatur hat keinen Zugriff auf
    /// die echte Keychain (-34018). Produktiv immer `nil`.
    private let memory: MemoryStorage?

    init(memory: MemoryStorage? = nil) { self.memory = memory }

    final class MemoryStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Data] = [:]
        func get(_ key: String) -> Data? { lock.withLock { values[key] } }
        func set(_ key: String, _ value: Data?) { lock.withLock { values[key] = value } }
    }

    func save(_ data: Data, account: String) throws {
        if let memory { memory.set(account, data); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }

    func load(account: String) throws -> Data? {
        if let memory { return memory.get(account) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return result as? Data
    }

    func delete(account: String) throws {
        if let memory { memory.set(account, nil); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

enum KeychainError: Error {
    case status(OSStatus)
}
