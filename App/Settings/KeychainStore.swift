import Foundation
import Security

enum KeychainStore {
    private static let service = "work.fenx.aibo"

    enum ReadResult<Value> {
        case found(Value)
        case notFound
        case failure(OSStatus)
    }

    static func string(forAccount account: String) -> String? {
        guard case .found(let value) = readString(forAccount: account) else { return nil }
        return value
    }

    static func readString(forAccount account: String) -> ReadResult<String> {
        switch readData(forAccount: account) {
        case .found(let data):
            if let text = String(data: data, encoding: .utf8) {
                return .found(text)
            }
            return .notFound
        case .notFound:
            return .notFound
        case .failure(let status):
            return .failure(status)
        }
    }

    static func data(forAccount account: String) -> Data? {
        guard case .found(let data) = readData(forAccount: account) else { return nil }
        return data
    }

    static func readData(forAccount account: String) -> ReadResult<Data> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return .found(data)
        }
        if status == errSecItemNotFound {
            return .notFound
        }
        return .failure(status)
    }

    static func setString(_ value: String, forAccount account: String) throws {
        try setData(Data(value.utf8), forAccount: account)
    }

    static func setData(_ data: Data, forAccount account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        if update != errSecItemNotFound {
            throw KeychainError.unhandled(update)
        }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let retry = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retry == errSecSuccess else { throw KeychainError.unhandled(retry) }
            return
        }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case unhandled(OSStatus)
    }
}
