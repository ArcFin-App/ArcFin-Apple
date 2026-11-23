// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Plugin v2 models

/// The plugin's dates are .NET DateTimes, which can come without a time zone; those are UTC.
private func pluginDate(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return JellyfinDate.parse(raw) ?? JellyfinDate.parse(raw + "Z")
}

/// A server sends null for a setting with no value; those are left out.
private func values(_ raw: [String: String?]?) -> [String: String] {
    (raw ?? [:]).compactMapValues { $0 }
}

public struct ArcfinSyncSetting: Sendable, Decodable, Equatable {
    public enum Source: String, Sendable, Decodable {
        case user, `default`, locked
    }

    public let key: String
    public let value: String?
    public let isLocked: Bool
    public let source: Source

    enum CodingKeys: String, CodingKey {
        case key = "Key", value = "Value", isLocked = "IsLocked", source = "Source"
    }

    public init(key: String, value: String?, isLocked: Bool, source: Source) {
        self.key = key
        self.value = value
        self.isLocked = isLocked
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        source = (try? container.decodeIfPresent(Source.self, forKey: .source)) ?? (isLocked ? .locked : .user)
    }
}

/// GET/PUT /ArcfinSync/Sync: the effective settings, and which device last changed them.
public struct ArcfinSyncState: Sendable, Decodable, Equatable {
    public let settings: [ArcfinSyncSetting]
    public let updatedAt: Date?
    public let updatedByDeviceId: String?
    public let updatedByDeviceName: String?

    enum CodingKeys: String, CodingKey {
        case settings = "Settings", updatedAt = "UpdatedAt"
        case updatedByDeviceId = "UpdatedByDeviceId", updatedByDeviceName = "UpdatedByDeviceName"
    }

    public init(settings: [ArcfinSyncSetting], updatedAt: Date?, updatedByDeviceId: String?, updatedByDeviceName: String?) {
        self.settings = settings
        self.updatedAt = updatedAt
        self.updatedByDeviceId = updatedByDeviceId
        self.updatedByDeviceName = updatedByDeviceName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent([ArcfinSyncSetting].self, forKey: .settings) ?? []
        updatedAt = pluginDate(try container.decodeIfPresent(String.self, forKey: .updatedAt))
        updatedByDeviceId = try container.decodeIfPresent(String.self, forKey: .updatedByDeviceId)
        updatedByDeviceName = try container.decodeIfPresent(String.self, forKey: .updatedByDeviceName)
    }

    public var values: [String: String] {
        var result: [String: String] = [:]
        for setting in settings { if let value = setting.value { result[setting.key] = value } }
        return result
    }

    public var lockedKeys: Set<String> { Set(settings.filter(\.isLocked).map(\.key)) }
}

/// One device signed in with Arcfin, as the plugin keeps it.
public struct ArcfinSyncDevice: Sendable, Decodable, Equatable, Identifiable {
    public let deviceId: String
    public let name: String
    public let customName: String?
    public let jellyfinDeviceName: String
    public let platform: String
    public let model: String?
    public let appVersion: String?
    public let syncMode: String
    public let lastSeen: Date?
    public let isCurrent: Bool
    public let settings: [String: String]

    public var id: String { deviceId }

    enum CodingKeys: String, CodingKey {
        case deviceId = "DeviceId", name = "Name", customName = "CustomName", jellyfinDeviceName = "JellyfinDeviceName"
        case platform = "Platform", model = "Model", appVersion = "AppVersion", syncMode = "SyncMode"
        case lastSeen = "LastSeen", isCurrent = "IsCurrent", settings = "Settings"
    }

    public init(deviceId: String, name: String, customName: String? = nil, jellyfinDeviceName: String = "",
                platform: String, model: String? = nil, appVersion: String? = nil, syncMode: String = "automatic",
                lastSeen: Date? = nil, isCurrent: Bool = false, settings: [String: String] = [:]) {
        self.deviceId = deviceId
        self.name = name
        self.customName = customName
        self.jellyfinDeviceName = jellyfinDeviceName
        self.platform = platform
        self.model = model
        self.appVersion = appVersion
        self.syncMode = syncMode
        self.lastSeen = lastSeen
        self.isCurrent = isCurrent
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        let jellyfinName = try container.decodeIfPresent(String.self, forKey: .jellyfinDeviceName) ?? ""
        jellyfinDeviceName = jellyfinName
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? jellyfinName
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
        platform = try container.decodeIfPresent(String.self, forKey: .platform) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        syncMode = try container.decodeIfPresent(String.self, forKey: .syncMode) ?? "automatic"
        lastSeen = pluginDate(try container.decodeIfPresent(String.self, forKey: .lastSeen))
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        settings = values(try container.decodeIfPresent([String: String?].self, forKey: .settings))
    }
}

/// PUT /ArcfinSync/Devices/Current. Who the device is comes from the sign-in, not from here.
public struct ArcfinSyncDeviceRegistration: Sendable, Encodable, Equatable {
    public var name: String?
    public var renameCurrent: Bool
    public var platform: String
    public var model: String
    public var appVersion: String
    public var syncMode: String
    public var settings: [String: String]

    enum CodingKeys: String, CodingKey {
        case name = "Name", renameCurrent = "RenameCurrent", platform = "Platform", model = "Model"
        case appVersion = "AppVersion", syncMode = "SyncMode", settings = "Settings"
    }

    public init(name: String? = nil, renameCurrent: Bool = false, platform: String, model: String, appVersion: String,
                syncMode: String, settings: [String: String]) {
        self.name = name
        self.renameCurrent = renameCurrent
        self.platform = platform
        self.model = model
        self.appVersion = appVersion
        self.syncMode = syncMode
        self.settings = settings
    }
}

/// An administrator's default and lock for one setting, for everyone or one user. A user's
/// entry with no lock of its own (nil) has everyone's lock; for everyone, nil is unlocked.
public struct ArcfinSyncPolicySetting: Sendable, Codable, Equatable {
    public var key: String
    public var defaultValue: String?
    public var locked: Bool?

    enum CodingKeys: String, CodingKey {
        case key = "Key", defaultValue = "DefaultValue", locked = "Locked"
    }

    public init(key: String, defaultValue: String?, locked: Bool?) {
        self.key = key
        self.defaultValue = defaultValue
        self.locked = locked
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked)
    }
}

public struct ArcfinSyncUserPolicy: Sendable, Codable, Equatable {
    public var userId: String
    public var settings: [ArcfinSyncPolicySetting]

    enum CodingKeys: String, CodingKey {
        case userId = "UserId", settings = "Settings"
    }

    public init(userId: String, settings: [ArcfinSyncPolicySetting]) {
        self.userId = userId
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        settings = try container.decodeIfPresent([ArcfinSyncPolicySetting].self, forKey: .settings) ?? []
    }
}

public struct ArcfinSyncPolicy: Sendable, Codable, Equatable {
    public var settings: [ArcfinSyncPolicySetting]
    public var users: [ArcfinSyncUserPolicy]

    enum CodingKeys: String, CodingKey {
        case settings = "Settings", users = "Users"
    }

    public init(settings: [ArcfinSyncPolicySetting] = [], users: [ArcfinSyncUserPolicy] = []) {
        self.settings = settings
        self.users = users
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent([ArcfinSyncPolicySetting].self, forKey: .settings) ?? []
        users = try container.decodeIfPresent([ArcfinSyncUserPolicy].self, forKey: .users) ?? []
    }
}

public struct ArcfinSyncAdminUser: Sendable, Decodable, Equatable, Identifiable {
    public let userId: String
    public let name: String
    public let isAdministrator: Bool
    public let devices: [ArcfinSyncDevice]
    public let settings: [String: String]

    public var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "UserId", name = "Name", isAdministrator = "IsAdministrator", devices = "Devices", settings = "Settings"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isAdministrator = try container.decodeIfPresent(Bool.self, forKey: .isAdministrator) ?? false
        devices = try container.decodeIfPresent([ArcfinSyncDevice].self, forKey: .devices) ?? []
        settings = values(try container.decodeIfPresent([String: String?].self, forKey: .settings))
    }
}

// MARK: - Plugin v2 endpoints

private struct SyncBody: Encodable {
    /// A null clears that setting.
    let values: [String: String?]
    let replace: Bool
    enum CodingKeys: String, CodingKey { case values = "Values", replace = "Replace" }
}

private struct NameBody: Encodable {
    let name: String
    enum CodingKeys: String, CodingKey { case name = "Name" }
}

extension ArcfinSyncClient {
    /// The served schema, as raw JSON; SyncEngine decodes it.
    public func fetchSchema(credential: ServerCredential, authHeader: String) async throws -> Data {
        try await send("GET", "Schema", credential: credential, authHeader: authHeader)
    }

    public func fetchSync(credential: ServerCredential, authHeader: String) async throws -> ArcfinSyncState {
        try decode(await send("GET", "Sync", credential: credential, authHeader: authHeader))
    }

    /// `replace`: this device's settings become everyone's, so a synced setting not in `values`
    /// goes back to its default. `clearing`: settings this device no longer has, cleared on the
    /// server too.
    public func updateSync(credential: ServerCredential, authHeader: String, values: [String: String],
                           clearing: Set<String> = [], replace: Bool) async throws -> ArcfinSyncState {
        var body: [String: String?] = values.mapValues { $0 }
        for key in clearing where values[key] == nil { body[key] = .some(nil) }
        return try decode(await send("PUT", "Sync", body: SyncBody(values: body, replace: replace),
                                     credential: credential, authHeader: authHeader))
    }

    public func registerDevice(credential: ServerCredential, authHeader: String,
                               _ registration: ArcfinSyncDeviceRegistration) async throws -> ArcfinSyncDevice {
        try decode(await send("PUT", "Devices/Current", body: registration, credential: credential, authHeader: authHeader))
    }

    public func fetchDevices(credential: ServerCredential, authHeader: String) async throws -> [ArcfinSyncDevice] {
        try decode(await send("GET", "Devices", credential: credential, authHeader: authHeader))
    }

    /// An empty name goes back to the device's Jellyfin name.
    public func renameDevice(credential: ServerCredential, authHeader: String, deviceID: String,
                             name: String) async throws -> ArcfinSyncDevice {
        try decode(await send("PUT", "Devices/\(Self.component(deviceID))/Name", body: NameBody(name: name),
                              credential: credential, authHeader: authHeader))
    }

    public func forgetDevice(credential: ServerCredential, authHeader: String, deviceID: String) async throws {
        _ = try await send("DELETE", "Devices/\(Self.component(deviceID))", credential: credential, authHeader: authHeader)
    }

    // Admin: the server checks the caller is an administrator.

    public func fetchPolicy(credential: ServerCredential, authHeader: String) async throws -> ArcfinSyncPolicy {
        try decode(await send("GET", "Admin/Policy", credential: credential, authHeader: authHeader))
    }

    /// What the server saved, which can differ from what was sent: it fills in a lock's value
    /// and drops what it doesn't keep. Read back when the answer doesn't say.
    public func updatePolicy(credential: ServerCredential, authHeader: String, _ policy: ArcfinSyncPolicy) async throws -> ArcfinSyncPolicy {
        let data = try await send("PUT", "Admin/Policy", body: policy, credential: credential, authHeader: authHeader)
        if let saved: ArcfinSyncPolicy = try? decode(data) { return saved }
        return try await fetchPolicy(credential: credential, authHeader: authHeader)
    }

    public func fetchAdminUsers(credential: ServerCredential, authHeader: String) async throws -> [ArcfinSyncAdminUser] {
        try decode(await send("GET", "Admin/Users", credential: credential, authHeader: authHeader))
    }

    public func adminRenameDevice(credential: ServerCredential, authHeader: String, userID: String, deviceID: String,
                                  name: String) async throws -> ArcfinSyncDevice {
        try decode(await send("PUT", "Admin/Users/\(Self.component(userID))/Devices/\(Self.component(deviceID))/Name",
                              body: NameBody(name: name), credential: credential, authHeader: authHeader))
    }

    public func adminForgetDevice(credential: ServerCredential, authHeader: String, userID: String, deviceID: String) async throws {
        _ = try await send("DELETE", "Admin/Users/\(Self.component(userID))/Devices/\(Self.component(deviceID))",
                           credential: credential, authHeader: authHeader)
    }

    // MARK: Plumbing

    static func component(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ method: String, _ path: String, body: (any Encodable)? = nil,
                      credential: ServerCredential, authHeader: String) async throws -> Data {
        guard let url = URL(string: "ArcfinSync/\(path)", relativeTo: Self.directory(credential.baseURL)) else {
            throw ArcfinSyncError.requestFailed
        }
        var req = URLRequest(url: url.absoluteURL)
        req.httpMethod = method
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let status = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw ArcfinSyncError.requestFailed
        }
        return data
    }

    /// The server's address as a directory, so a relative path keeps a base path like /jellyfin.
    private static func directory(_ base: URL) -> URL {
        base.absoluteString.hasSuffix("/") ? base : URL(string: base.absoluteString + "/") ?? base
    }
}
