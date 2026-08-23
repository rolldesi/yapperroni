import Foundation
import Security

/// API keys live in the login Keychain, never in UserDefaults.
///
/// UserDefaults is a plist any process running as this user can read, and it
/// gets copied around by backups and sync. A transcription key is a billable
/// credential; it belongs behind the same door as a password.
enum Keychain {
    private static let service = "com.rahuldesai.yapperroni"

    static func set(_ value: String, for account: String) {
        // Delete-then-add rather than update: simpler, and it cannot leave a
        // stale item behind if the attributes ever change.
        remove(account)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Status code only — never the key, and never the error's payload.
            Log.write("keychain write failed for \(account) (OSStatus \(status))")
        }
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8)
        else { return nil }
        return s
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func has(_ account: String) -> Bool { get(account) != nil }
}
