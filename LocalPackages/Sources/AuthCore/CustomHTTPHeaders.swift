// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Security

/// Extra HTTP headers for a Jellyfin server behind an access gateway (Cloudflare Access
/// service tokens, Pangolin, a reverse proxy's shared secret). Each server keeps its own, and
/// they're only added to requests for that server's addresses: its sign-in address and its
/// Local and Remote URLs. Kept in the Keychain since they're usually credentials, and cached
/// in memory because every request reads them.
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

    /// Whose headers the editor shows and saves.
    public enum Scope: Sendable {
        /// A signed-in profile's server.
        case server(ServerCredential)
        /// The address being signed in to, as typed.
        case address(String)
        /// No server known yet.
        case unassigned
    }

    struct Server: Codable, Sendable, Equatable {
        /// `host` for the default ports, `host:port` otherwise.
        var origins: [String]
        /// Profiles on this server, whose Local and Remote URLs count as its addresses too.
        var profileIDs: [UUID]
        var headers: [Header]
    }

    struct Stored: Codable, Sendable, Equatable {
        var servers: [Server] = []
        /// Entered before any server was known, or saved by an older version with no profile
        /// signed in. Not sent anywhere until saved for a server.
        var unassigned: [Header] = []
    }

    private static let service = "com.psmattas.arcfin.custom-headers"
    /// Before 0.5.0 one list was kept for the whole device.
    private static let legacyAccount = "headers"
    private static let account = "servers"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: Stored?

    /// The headers to add to a request for `url`: the matching server's, without blank names
    /// or the Authorization header Jellyfin itself needs. Empty for any other host.
    public static func headers(for url: URL?) -> [String: String] {
        guard let url, let server = server(for: url, in: stored(), addresses: savedAddresses) else { return [:] }
        return sendable(server.headers)
    }

    /// The saved headers for the editor, as entered.
    public static func headers(in scope: Scope) -> [Header] {
        let stored = stored()
        if let index = index(of: scope, in: stored, addresses: savedAddresses) { return stored.servers[index].headers }
        if case .server = scope { return [] }
        return stored.unassigned
    }

    public static func save(_ headers: [Header], in scope: Scope) throws {
        lock.lock()
        defer { lock.unlock() }
        var stored = try cache ?? readMigrating()
        update(&stored, headers: headers, scope: scope, addresses: savedAddresses)
        try write(stored)
        cache = stored
    }

    public static func removeAll() {
        delete(account: account)
        delete(account: legacyAccount)
        lock.lock()
        cache = Stored()
        lock.unlock()
    }

    // MARK: - Matching

    static func origin(of url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        guard let port = url.port, port != 80, port != 443 else { return host }
        return "\(host):\(port)"
    }

    static func origin(ofAddress address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)").flatMap(origin(of:))
    }

    static func origins(of server: Server, addresses: (UUID) -> [String]) -> Set<String> {
        var result = Set(server.origins)
        for id in server.profileIDs {
            for address in addresses(id) { if let origin = origin(ofAddress: address) { result.insert(origin) } }
        }
        return result
    }

    static func server(for url: URL, in stored: Stored, addresses: (UUID) -> [String]) -> Server? {
        guard let origin = origin(of: url) else { return nil }
        return stored.servers.first { origins(of: $0, addresses: addresses).contains(origin) }
    }

    static func index(of scope: Scope, in stored: Stored, addresses: (UUID) -> [String]) -> Int? {
        switch scope {
        case .server(let credential):
            let origin = origin(of: credential.baseURL)
            return stored.servers.firstIndex { $0.profileIDs.contains(credential.id) }
                ?? origin.flatMap { origin in
                    stored.servers.firstIndex { origins(of: $0, addresses: addresses).contains(origin) }
                }
        case .address(let address):
            guard let origin = origin(ofAddress: address) else { return nil }
            return stored.servers.firstIndex { origins(of: $0, addresses: addresses).contains(origin) }
        case .unassigned:
            return nil
        }
    }

    static func update(_ stored: inout Stored, headers: [Header], scope: Scope, addresses: (UUID) -> [String]) {
        let target: (origin: String?, profileID: UUID?)
        switch scope {
        case .server(let credential): target = (origin(of: credential.baseURL), credential.id)
        case .address(let address): target = (origin(ofAddress: address), nil)
        case .unassigned: target = (nil, nil)
        }
        guard target.origin != nil || target.profileID != nil else {
            stored.unassigned = headers
            return
        }
        if case .address = scope { stored.unassigned = [] }
        if let index = index(of: scope, in: stored, addresses: addresses) {
            if headers.isEmpty {
                stored.servers.remove(at: index)
                return
            }
            stored.servers[index].headers = headers
            if let origin = target.origin, !stored.servers[index].origins.contains(origin) {
                stored.servers[index].origins.append(origin)
            }
            if let id = target.profileID, !stored.servers[index].profileIDs.contains(id) {
                stored.servers[index].profileIDs.append(id)
            }
        } else if !headers.isEmpty {
            stored.servers.append(Server(origins: target.origin.map { [$0] } ?? [],
                                         profileIDs: target.profileID.map { [$0] } ?? [],
                                         headers: headers))
        }
    }

    private static func sendable(_ headers: [Header]) -> [String: String] {
        var result: [String: String] = [:]
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.caseInsensitiveCompare("Authorization") != .orderedSame else { continue }
            result[name] = header.value.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// A profile's Local and Remote URLs, read live so a change in Server Settings applies at once.
    private static func savedAddresses(_ profileID: UUID) -> [String] {
        let defaults = UserDefaults.standard
        return ["serverLocalURL.\(profileID.uuidString)", "serverRemoteURL.\(profileID.uuidString)"]
            .compactMap { defaults.string(forKey: $0) }
    }

    // MARK: - Keychain

    /// A failed read (the device still locked since starting, say) isn't cached, so the next
    /// request tries again instead of going without headers for the rest of the run.
    private static func stored() -> Stored {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        guard let stored = try? readMigrating() else { return Stored() }
        cache = stored
        return stored
    }

    /// Moves an older version's single list to the profile in use (or the first one, as the
    /// launch does), keeping the old item until the new one is written and reads back the same.
    private static func readMigrating() throws -> Stored {
        if let data = try read(account: account) {
            delete(account: legacyAccount)
            return (try? JSONDecoder().decode(Stored.self, from: data)) ?? Stored()
        }
        guard let legacy = try read(account: legacyAccount) else { return Stored() }
        let headers = (try? JSONDecoder().decode([Header].self, from: legacy)) ?? []
        var stored = Stored()
        if !headers.isEmpty {
            let activeID = UserDefaults.standard.string(forKey: "arcfin.activeProfileID").flatMap { UUID(uuidString: $0) }
            stored = try migrated(headers, profiles: KeychainStore().allServers(), activeID: activeID)
        }
        try write(stored)
        guard let written = try read(account: account),
              (try? JSONDecoder().decode(Stored.self, from: written)) == stored
        else { throw KeychainError.decodingFailed }
        delete(account: legacyAccount)
        return stored
    }

    /// No profiles while one is still marked in use means they couldn't be read yet: try later
    /// rather than leave the headers with no server.
    static func migrated(_ headers: [Header], profiles: [ServerCredential], activeID: UUID?) throws -> Stored {
        guard let profile = profiles.first(where: { $0.id == activeID }) ?? profiles.first else {
            guard activeID == nil else { throw KeychainError.decodingFailed }
            return Stored(unassigned: headers)
        }
        return Stored(servers: [Server(origins: origin(of: profile.baseURL).map { [$0] } ?? [],
                                       profileIDs: [profile.id], headers: headers)])
    }

    private static func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    /// nil when there's no such item; throws when the Keychain can't be read.
    private static func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = ref as? Data else { throw KeychainError.unexpectedStatus(status) }
        return data
    }

    private static func write(_ stored: Stored) throws {
        let data = try JSONEncoder().encode(stored)
        let query = baseQuery(account: account)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
