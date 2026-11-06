import Foundation
import Security

enum AIKeychainService {
    private static let service = "com.example.Daymark.AI"
    private static let accountPrefix = "provider-api-key:"

    static func saveAPIKey(_ apiKey: String, for providerID: UUID) -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteAPIKey(for: providerID) }
        guard let data = trimmed.data(using: .utf8) else { return false }
        let account = accountPrefix + providerID.uuidString.lowercased()
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var addAttributes = baseQuery
        addAttributes[kSecValueData as String] = data
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(addAttributes as CFDictionary, nil) == errSecSuccess
    }

    static func loadAPIKey(for providerID: UUID) -> String? {
        let account = accountPrefix + providerID.uuidString.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty else { return nil }
        return string
    }

    static func hasAPIKey(for providerID: UUID) -> Bool {
        loadAPIKey(for: providerID) != nil
    }

    @discardableResult
    static func deleteAPIKey(for providerID: UUID) -> Bool {
        let account = accountPrefix + providerID.uuidString.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

enum AISecretRedactor {
    static func redact(_ text: String, apiKey: String?) -> String {
        guard let apiKey, !apiKey.isEmpty else { return text }
        return text.replacingOccurrences(of: apiKey, with: "•••")
    }
}
