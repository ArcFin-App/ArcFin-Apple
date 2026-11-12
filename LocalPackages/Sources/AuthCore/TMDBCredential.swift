// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Security

/// The user's own TMDB API key (or read access token), kept in the Keychain.
public enum TMDBCredential {
    private static let service = "com.psmattas.arcfin.tmdb"
    private static let account = "key"

    public static func load() -> String? { load(account: account) }

    /// An empty key removes it.
    public static func save(_ key: String) throws { try save(key, account: account) }

    /// A profile's own key, kept aside while another profile is active.
    public static func load(profile: UUID) -> String? { load(account: "key.\(profile.uuidString)") }

    public static func save(_ key: String, profile: UUID) throws { try save(key, account: "key.\(profile.uuidString)") }

    private static func load(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    private static func save(_ key: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }
}
