// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Security

/// Extra HTTP headers sent with every request to the Jellyfin server, its images and its
/// streams: for servers behind an access gateway (Cloudflare Access service tokens, Pangolin,
/// a reverse proxy's shared secret). Kept in the Keychain since they're usually credentials,
/// and cached in memory because every request reads them.
public enum CustomHTTPHeaders {
    public struct Header: Codable, Sendable, Equatable, Identifiable {
        public var id = UUID()
        public var name: String
        public var value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    private static let service = "com.psmattas.arcfin.custom-headers"
    private static let account = "headers"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Header]?

    /// The saved headers, as entered.
    public static var all: [Header] {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let loaded = load()
        cache = loaded
        return loaded
    }

    /// The headers to send. Blank names, and the Authorization header Jellyfin itself needs,
    /// are left out.
    public static var current: [String: String] {
        var result: [String: String] = [:]
        for header in all {
            let name = header.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.caseInsensitiveCompare("Authorization") != .orderedSame else { continue }
            result[name] = header.value.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    public static func save(_ headers: [Header]) throws {
        let data = try JSONEncoder().encode(headers)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        lock.lock()
        cache = headers
        lock.unlock()
    }

    public static func removeAll() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
        SecItemDelete(query as CFDictionary)
        lock.lock()
        cache = []
        lock.unlock()
    }

    private static func load() -> [Header] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess, let data = ref as? Data else { return [] }
        return (try? JSONDecoder().decode([Header].self, from: data)) ?? []
    }
}
