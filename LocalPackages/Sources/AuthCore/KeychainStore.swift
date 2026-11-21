// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Security

public enum KeychainError: Error, Sendable {
    case unexpectedStatus(OSStatus)
    case decodingFailed
}

public final class KeychainStore: KeychainClientProtocol, @unchecked Sendable {

    private let service    = "com.psmattas.arcfin"
    private let pinService = "com.psmattas.arcfin.pin"
    private let seerrService = "com.psmattas.arcfin.seerr"
    private let seerrAccount = "password"
    /// Sign-ins and the Seerr password stay readable while the device is locked, once it has
    /// been unlocked since starting: CarPlay, Lock Screen music buttons, Siri and background
    /// refresh all start the app then. Before 0.5.0 they were saved "when unlocked".
    private let accessible = kSecAttrAccessibleAfterFirstUnlock

    public init() {}

    public func save(_ credential: ServerCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let account = credential.id.uuidString
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            // macOS defaults SecItem* to the legacy file-based login keychain unless told
            // otherwise, which scopes items to the running binary's ad-hoc/dev code
            // signature — a fresh build from Xcode gets a different implicit access group
            // each time, so items saved by a previous run silently stop resolving on the
            // next launch (looks like sign-in "didn't persist" even though the save appeared
            // to succeed). This opts into the same per-container Data Protection Keychain
            // iOS already uses unconditionally, which doesn't have that instability. A no-op
            // on iOS/tvOS, where it's already the default.
            kSecUseDataProtectionKeychain: true,
        ]
        let attrs: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: accessible]
        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = accessible
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Moves the sign-ins and Seerr passwords saved before 0.5.0 to `accessible`. The items are
    /// updated in place, so nothing is deleted or rewritten; if it fails they stay as they were.
    /// Needs the device unlocked.
    public func upgradeAccessibility() throws {
        for itemService in [service, seerrService] {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: itemService,
                kSecUseDataProtectionKeychain: true,
            ]
            let status = SecItemUpdate(query as CFDictionary, [kSecAttrAccessible: accessible] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }

    public func load(serverID: UUID) throws -> ServerCredential? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: serverID.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = ref as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return try JSONDecoder().decode(ServerCredential.self, from: data)
    }

    public func delete(serverID: UUID) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: serverID.uuidString,
            kSecUseDataProtectionKeychain: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func allServers() throws -> [ServerCredential] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecUseDataProtectionKeychain: true,
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = ref as? [Data] else {
            throw KeychainError.unexpectedStatus(status)
        }
        return items.compactMap { try? JSONDecoder().decode(ServerCredential.self, from: $0) }
    }

    // MARK: - PIN storage (separate service, device-only accessibility)

    public func savePin(_ pin: String, for credentialID: UUID) throws {
        guard let data = pin.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     pinService,
            kSecAttrAccount:     credentialID.uuidString,
            kSecAttrAccessible:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
        ]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func loadPin(for credentialID: UUID) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  pinService,
            kSecAttrAccount:  credentialID.uuidString,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = ref as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func deletePin(for credentialID: UUID) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: pinService,
            kSecAttrAccount: credentialID.uuidString,
            kSecUseDataProtectionKeychain: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Seerr password (separate service — was previously plain UserDefaults)

    public func saveSeerrPassword(_ password: String) throws {
        try saveSeerr(password, account: seerrAccount)
    }

    public func loadSeerrPassword() throws -> String? {
        try loadSeerr(account: seerrAccount)
    }

    public func deleteSeerrPassword() throws {
        try deleteSeerr(account: seerrAccount)
    }

    // Each profile's own Seerr password, set aside while another profile is active.

    public func saveSeerrPassword(_ password: String, profile: UUID) throws {
        try saveSeerr(password, account: "\(seerrAccount).\(profile.uuidString)")
    }

    public func loadSeerrPassword(profile: UUID) throws -> String? {
        try loadSeerr(account: "\(seerrAccount).\(profile.uuidString)")
    }

    public func deleteSeerrPassword(profile: UUID) throws {
        try deleteSeerr(account: "\(seerrAccount).\(profile.uuidString)")
    }

    private func saveSeerr(_ password: String, account: String) throws {
        guard let data = password.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: seerrService,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data, kSecAttrAccessible: accessible] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = accessible
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private func loadSeerr(account: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: seerrService,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = ref as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSeerr(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: seerrService,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
