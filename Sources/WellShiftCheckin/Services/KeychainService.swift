import Foundation
import Security

/// Notion Integration Token / Claude APIキーを macOS Keychain に安全に保存する。
/// 平文でのファイル保存（UserDefaults含む）は行わない。
enum KeychainKey: String {
    case notionToken = "com.nacchan.wellshift.notionToken"
    case claudeAPIKey = "com.nacchan.wellshift.claudeAPIKey"
}

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let service = "com.nacchan.wellshift.WellShiftCheckin"

    @discardableResult
    func save(_ value: String, for key: KeychainKey) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        // 既存があれば削除してから追加（更新も兼ねる）
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func read(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    func delete(_ key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    var hasNotionToken: Bool { read(.notionToken)?.isEmpty == false }
    var hasClaudeAPIKey: Bool { read(.claudeAPIKey)?.isEmpty == false }
}
