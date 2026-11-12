// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Models

/// The server as its dashboard describes it.
public struct JellyfinSystemInfo: Sendable, Equatable {
    public let serverName: String
    public let version: String
    public let operatingSystem: String?
    public let hasUpdateAvailable: Bool
    public let hasPendingRestart: Bool
    public let isShuttingDown: Bool
    public let localAddress: String?
}

/// A task the server runs on a schedule (library scan, metadata refresh, cleanups).
public struct JellyfinScheduledTask: Sendable, Identifiable, Equatable {
    public enum State: String, Sendable { case idle = "Idle", running = "Running", cancelling = "Cancelling" }

    public let id: String
    public let name: String
    public let category: String
    public let description: String?
    public let state: State
    /// 0–100 while running.
    public let progress: Double?
    public let lastRunStart: Date?
    public let lastRunEnd: Date?
    /// "Completed", "Failed", "Cancelled" or "Aborted".
    public let lastResult: String?
    public let lastError: String?
}

/// One entry in the server's activity log.
public struct JellyfinActivityEntry: Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let type: String
    public let date: Date?
    /// "Information", "Warning" or "Error".
    public let severity: String
}

/// A library as the server configures it: its folders and kind.
public struct JellyfinLibraryFolder: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let collectionType: String?
    public let locations: [String]
    /// 0–100 while the library scans.
    public let refreshProgress: Double?
}

/// A server user, with the permissions the admin screens show.
public struct JellyfinUser: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let hasPassword: Bool
    public let lastActivity: Date?
    public let isAdministrator: Bool
    public let isDisabled: Bool
    public let primaryImageTag: String?
}

/// A device that has signed in to the server.
public struct JellyfinDevice: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let appName: String
    public let appVersion: String?
    public let lastUserName: String?
    public let lastActivity: Date?
}

/// An installed server plugin.
public struct JellyfinPlugin: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    /// "Active", "Disabled", "Restart", "NotSupported", "Malfunctioned", "Superceded", "Deleted".
    public let status: String
    public let canUninstall: Bool
}

/// A plugin in the server's catalogue, with its newest version.
public struct JellyfinPackage: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let overview: String?
    public let category: String?
    public let latestVersion: String?
    public let repositoryUrl: String?
}

/// An API key the server hands out to apps.
public struct JellyfinAPIKey: Sendable, Identifiable, Equatable {
    public let token: String
    public let appName: String
    public let created: Date?
    public var id: String { token }
}

/// One of the server's log files.
public struct JellyfinLogFile: Sendable, Identifiable, Equatable {
    public let name: String
    public let size: Int64
    public let modified: Date?
    public var id: String { name }
}

/// A server backup (Jellyfin 10.11 and later).
public struct JellyfinBackup: Sendable, Identifiable, Equatable {
    public let path: String
    public let serverVersion: String?
    public let created: Date?
    public var id: String { path }
}

// MARK: - Client

/// The server's admin endpoints. Every call needs an administrator's session.
public struct JellyfinAdminClient: Sendable {
    public init() {}

    public func systemInfo(credential: ServerCredential, authHeader: String) async throws -> JellyfinSystemInfo {
        let response: SystemInfoResponse = try await get("System/Info", credential: credential, authHeader: authHeader)
        return JellyfinSystemInfo(
            serverName: response.serverName ?? "", version: response.version ?? "",
            operatingSystem: response.operatingSystemDisplayName,
            hasUpdateAvailable: response.hasUpdateAvailable ?? false,
            hasPendingRestart: response.hasPendingRestart ?? false,
            isShuttingDown: response.isShuttingDown ?? false,
            localAddress: response.localAddress)
    }

    public func restart(credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "System/Restart", credential: credential, authHeader: authHeader)
    }

    public func shutDown(credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "System/Shutdown", credential: credential, authHeader: authHeader)
    }

    public func scheduledTasks(credential: ServerCredential, authHeader: String) async throws -> [JellyfinScheduledTask] {
        let response: [ScheduledTaskResponse] = try await get(
            "ScheduledTasks", query: [.init(name: "isHidden", value: "false")], credential: credential, authHeader: authHeader)
        return response.map { task in
            JellyfinScheduledTask(
                id: task.id, name: task.name, category: task.category ?? "",
                description: task.description,
                state: JellyfinScheduledTask.State(rawValue: task.state ?? "") ?? .idle,
                progress: task.currentProgressPercentage,
                lastRunStart: task.lastExecutionResult?.startTimeUtc.flatMap(JellyfinDate.parse),
                lastRunEnd: task.lastExecutionResult?.endTimeUtc.flatMap(JellyfinDate.parse),
                lastResult: task.lastExecutionResult?.status,
                lastError: task.lastExecutionResult?.errorMessage)
        }
    }

    public func startTask(id: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "ScheduledTasks/Running/\(id)", credential: credential, authHeader: authHeader)
    }

    public func stopTask(id: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("DELETE", "ScheduledTasks/Running/\(id)", credential: credential, authHeader: authHeader)
    }

    public func activity(startIndex: Int = 0, limit: Int = 50, credential: ServerCredential, authHeader: String) async throws -> [JellyfinActivityEntry] {
        let response: ActivityPage = try await get(
            "System/ActivityLog/Entries",
            query: [.init(name: "startIndex", value: "\(startIndex)"), .init(name: "limit", value: "\(limit)")],
            credential: credential, authHeader: authHeader)
        return response.items.map {
            JellyfinActivityEntry(id: $0.id, name: $0.name, overview: $0.shortOverview ?? $0.overview,
                                  type: $0.type ?? "", date: $0.date.flatMap(JellyfinDate.parse),
                                  severity: $0.severity ?? "Information")
        }
    }

    // MARK: Libraries

    public func libraries(credential: ServerCredential, authHeader: String) async throws -> [JellyfinLibraryFolder] {
        let response: [VirtualFolderResponse] = try await get("Library/VirtualFolders", credential: credential, authHeader: authHeader)
        return response.map {
            JellyfinLibraryFolder(id: $0.itemId ?? $0.name, name: $0.name, collectionType: $0.collectionType,
                                  locations: $0.locations ?? [], refreshProgress: $0.refreshProgress)
        }
    }

    /// Scans every library for new and changed files.
    public func scanAllLibraries(credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "Library/Refresh", credential: credential, authHeader: authHeader)
    }

    /// Scans one library; `replaceMetadata` also fetches every title's details again.
    public func scanLibrary(id: String, replaceMetadata: Bool = false, credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "Items/\(id)/Refresh", query: [
            .init(name: "Recursive", value: "true"),
            .init(name: "MetadataRefreshMode", value: replaceMetadata ? "FullRefresh" : "Default"),
            .init(name: "ImageRefreshMode", value: replaceMetadata ? "FullRefresh" : "Default"),
            .init(name: "ReplaceAllMetadata", value: replaceMetadata ? "true" : "false"),
            .init(name: "ReplaceAllImages", value: "false"),
        ], credential: credential, authHeader: authHeader)
    }

    public func addLibraryFolder(library: String, path: String, credential: ServerCredential, authHeader: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["Name": library, "PathInfo": ["Path": path]])
        try await send("POST", "Library/VirtualFolders/Paths", query: [.init(name: "refreshLibrary", value: "true")],
                       body: body, credential: credential, authHeader: authHeader)
    }

    public func removeLibraryFolder(library: String, path: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("DELETE", "Library/VirtualFolders/Paths", query: [
            .init(name: "name", value: library), .init(name: "path", value: path), .init(name: "refreshLibrary", value: "true"),
        ], credential: credential, authHeader: authHeader)
    }

    public func renameLibrary(_ name: String, to newName: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "Library/VirtualFolders/Name", query: [
            .init(name: "name", value: name), .init(name: "newName", value: newName), .init(name: "refreshLibrary", value: "true"),
        ], credential: credential, authHeader: authHeader)
    }

    /// `collectionType`: movies, tvshows, music, musicvideos, homevideos, boxsets, books, mixed (nil).
    public func addLibrary(name: String, collectionType: String?, paths: [String], credential: ServerCredential, authHeader: String) async throws {
        var query: [URLQueryItem] = [.init(name: "name", value: name), .init(name: "refreshLibrary", value: "true")]
        if let collectionType { query.append(.init(name: "collectionType", value: collectionType)) }
        query += paths.map { .init(name: "paths", value: $0) }
        let body = try JSONSerialization.data(withJSONObject: ["LibraryOptions": [String: Any]()])
        try await send("POST", "Library/VirtualFolders", query: query, body: body, credential: credential, authHeader: authHeader)
    }

    /// Removes the library from the server. Its files on disk stay.
    public func removeLibrary(name: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("DELETE", "Library/VirtualFolders", query: [
            .init(name: "name", value: name), .init(name: "refreshLibrary", value: "true"),
        ], credential: credential, authHeader: authHeader)
    }

    /// The folders in a directory on the server's own disk, for picking a library folder.
    /// An empty `path` lists the drives (or `/` on Linux and macOS).
    public func directories(at path: String, credential: ServerCredential, authHeader: String) async throws -> [String] {
        let response: [FileSystemEntry] = path.isEmpty
            ? try await get("Environment/Drives", credential: credential, authHeader: authHeader)
            : try await get("Environment/DirectoryContents", query: [
                .init(name: "path", value: path), .init(name: "includeFiles", value: "false"),
                .init(name: "includeDirectories", value: "true"),
            ], credential: credential, authHeader: authHeader)
        return response.map(\.path).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Users

    public func users(credential: ServerCredential, authHeader: String) async throws -> [JellyfinUser] {
        let response: [UserResponse] = try await get("Users", credential: credential, authHeader: authHeader)
        return response.map {
            JellyfinUser(id: $0.id, name: $0.name, hasPassword: $0.hasPassword ?? true,
                         lastActivity: $0.lastActivityDate.flatMap(JellyfinDate.parse),
                         isAdministrator: $0.policy?.isAdministrator ?? false,
                         isDisabled: $0.policy?.isDisabled ?? false, primaryImageTag: $0.primaryImageTag)
        }
    }

    @discardableResult
    public func createUser(name: String, password: String, credential: ServerCredential, authHeader: String) async throws -> String? {
        let body = try JSONSerialization.data(withJSONObject: ["Name": name, "Password": password])
        let data = try await send("POST", "Users/New", body: body, credential: credential, authHeader: authHeader)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["Id"] as? String
    }

    public func deleteUser(id: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("DELETE", "Users/\(id)", credential: credential, authHeader: authHeader)
    }

    /// Sets a user's password as an admin, without their current one. Empty clears it.
    public func setPassword(userId: String, to password: String, credential: ServerCredential, authHeader: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["NewPw": password])
        try await send("POST", "Users/\(userId)/Password", body: body, credential: credential, authHeader: authHeader)
    }

    /// The user's policy as the server sends it (JSON), so a change can post every field back,
    /// including ones this app doesn't know about.
    public func policy(userId: String, credential: ServerCredential, authHeader: String) async throws -> Data {
        let data = try await send("GET", "Users/\(userId)", credential: credential, authHeader: authHeader)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let policy = object["Policy"] else { throw URLError(.cannotParseResponse) }
        return try JSONSerialization.data(withJSONObject: policy)
    }

    public func setPolicy(userId: String, _ policy: Data, credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "Users/\(userId)/Policy", body: policy, credential: credential, authHeader: authHeader)
    }

    // MARK: Devices

    public func devices(credential: ServerCredential, authHeader: String) async throws -> [JellyfinDevice] {
        let response: DevicesPage = try await get("Devices", credential: credential, authHeader: authHeader)
        return response.items.map {
            JellyfinDevice(id: $0.id, name: $0.name ?? $0.id, appName: $0.appName ?? "", appVersion: $0.appVersion,
                           lastUserName: $0.lastUserName, lastActivity: $0.dateLastActivity.flatMap(JellyfinDate.parse))
        }
    }

    /// Signs the device out and forgets it; it has to sign in again.
    public func deleteDevice(id: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("DELETE", "Devices", query: [.init(name: "id", value: id)], credential: credential, authHeader: authHeader)
    }

    // MARK: Plugins

    public func plugins(credential: ServerCredential, authHeader: String) async throws -> [JellyfinPlugin] {
        let response: [PluginResponse] = try await get("Plugins", credential: credential, authHeader: authHeader)
        return response.map {
            JellyfinPlugin(id: $0.id, name: $0.name, version: $0.version ?? "", description: $0.description,
                           status: $0.status ?? "Active", canUninstall: $0.canUninstall ?? false)
        }
    }

    public func setPlugin(_ plugin: JellyfinPlugin, enabled: Bool, credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "Plugins/\(plugin.id)/\(plugin.version)/\(enabled ? "Enable" : "Disable")",
                       credential: credential, authHeader: authHeader)
    }

    public func uninstall(_ plugin: JellyfinPlugin, credential: ServerCredential, authHeader: String) async throws {
        try await send("DELETE", "Plugins/\(plugin.id)/\(plugin.version)", credential: credential, authHeader: authHeader)
    }

    public func catalogue(credential: ServerCredential, authHeader: String) async throws -> [JellyfinPackage] {
        let response: [PackageResponse] = try await get("Packages", credential: credential, authHeader: authHeader)
        return response.compactMap { package in
            guard let guid = package.guid else { return nil }
            let latest = package.versions?.first
            return JellyfinPackage(id: guid, name: package.name, overview: package.overview ?? package.description,
                                   category: package.category, latestVersion: latest?.version,
                                   repositoryUrl: latest?.repositoryUrl)
        }
    }

    /// Installs a catalogue plugin, or updates an installed one to `version`. It takes
    /// effect after the server restarts.
    public func install(_ package: JellyfinPackage, version: String? = nil, credential: ServerCredential, authHeader: String) async throws {
        var query: [URLQueryItem] = [.init(name: "assemblyGuid", value: package.id)]
        if let version = version ?? package.latestVersion { query.append(.init(name: "version", value: version)) }
        if let repository = package.repositoryUrl { query.append(.init(name: "repositoryUrl", value: repository)) }
        let name = package.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? package.name
        try await send("POST", "Packages/Installed/\(name)", query: query, credential: credential, authHeader: authHeader)
    }

    // MARK: API keys

    public func apiKeys(credential: ServerCredential, authHeader: String) async throws -> [JellyfinAPIKey] {
        let response: KeysPage = try await get("Auth/Keys", credential: credential, authHeader: authHeader)
        return response.items.map {
            JellyfinAPIKey(token: $0.accessToken, appName: $0.appName ?? "", created: $0.dateCreated.flatMap(JellyfinDate.parse))
        }
    }

    public func createAPIKey(appName: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("POST", "Auth/Keys", query: [.init(name: "app", value: appName)], credential: credential, authHeader: authHeader)
    }

    public func revokeAPIKey(_ token: String, credential: ServerCredential, authHeader: String) async throws {
        try await send("DELETE", "Auth/Keys/\(token)", credential: credential, authHeader: authHeader)
    }

    // MARK: Logs

    public func logFiles(credential: ServerCredential, authHeader: String) async throws -> [JellyfinLogFile] {
        let response: [LogFileResponse] = try await get("System/Logs", credential: credential, authHeader: authHeader)
        return response.map {
            JellyfinLogFile(name: $0.name, size: $0.size ?? 0, modified: $0.dateModified.flatMap(JellyfinDate.parse))
        }
        .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    public func logFile(named name: String, credential: ServerCredential, authHeader: String) async throws -> String {
        let data = try await send("GET", "System/Logs/Log", query: [.init(name: "name", value: name)],
                                  credential: credential, authHeader: authHeader)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Backups

    /// The server's backups, newest first. Throws on servers before 10.11, which have none.
    public func backups(credential: ServerCredential, authHeader: String) async throws -> [JellyfinBackup] {
        let response: [BackupResponse] = try await get("Backup", credential: credential, authHeader: authHeader)
        return response.map {
            JellyfinBackup(path: $0.path, serverVersion: $0.serverVersion, created: $0.dateCreated.flatMap(JellyfinDate.parse))
        }
        .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }

    /// Backs up the database and settings, and optionally metadata, trickplay and subtitles.
    public func createBackup(metadata: Bool, trickplay: Bool, subtitles: Bool, credential: ServerCredential, authHeader: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "Metadata": metadata, "Trickplay": trickplay, "Subtitles": subtitles, "Database": true,
        ])
        try await send("POST", "Backup/Create", body: body, credential: credential, authHeader: authHeader)
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], credential: ServerCredential, authHeader: String) async throws -> T {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.arcfin.data(for: req)
        try Self.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
              credential: ServerCredential, authHeader: String) async throws -> Data {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.timeoutInterval = 30
        let (data, response) = try await URLSession.arcfin.data(for: req)
        try Self.check(response)
        return data
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw http.statusCode == 401 || http.statusCode == 403 ? URLError(.userAuthenticationRequired) : URLError(.badServerResponse)
        }
    }
}

// MARK: - Responses

private struct SystemInfoResponse: Decodable {
    let serverName: String?
    let version: String?
    let operatingSystemDisplayName: String?
    let hasUpdateAvailable: Bool?
    let hasPendingRestart: Bool?
    let isShuttingDown: Bool?
    let localAddress: String?
    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName", version = "Version", operatingSystemDisplayName = "OperatingSystemDisplayName"
        case hasUpdateAvailable = "HasUpdateAvailable", hasPendingRestart = "HasPendingRestart"
        case isShuttingDown = "IsShuttingDown", localAddress = "LocalAddress"
    }
}

private struct ScheduledTaskResponse: Decodable {
    struct Result: Decodable {
        let startTimeUtc: String?
        let endTimeUtc: String?
        let status: String?
        let errorMessage: String?
        enum CodingKeys: String, CodingKey {
            case startTimeUtc = "StartTimeUtc", endTimeUtc = "EndTimeUtc", status = "Status", errorMessage = "ErrorMessage"
        }
    }
    let id: String
    let name: String
    let category: String?
    let description: String?
    let state: String?
    let currentProgressPercentage: Double?
    let lastExecutionResult: Result?
    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", category = "Category", description = "Description", state = "State"
        case currentProgressPercentage = "CurrentProgressPercentage", lastExecutionResult = "LastExecutionResult"
    }
}

private struct ActivityPage: Decodable {
    struct Entry: Decodable {
        let id: Int
        let name: String
        let overview: String?
        let shortOverview: String?
        let type: String?
        let date: String?
        let severity: String?
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", overview = "Overview", shortOverview = "ShortOverview"
            case type = "Type", date = "Date", severity = "Severity"
        }
    }
    let items: [Entry]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct VirtualFolderResponse: Decodable {
    let name: String
    let itemId: String?
    let collectionType: String?
    let locations: [String]?
    let refreshProgress: Double?
    enum CodingKeys: String, CodingKey {
        case name = "Name", itemId = "ItemId", collectionType = "CollectionType", locations = "Locations"
        case refreshProgress = "RefreshProgress"
    }
}

private struct FileSystemEntry: Decodable {
    let path: String
    enum CodingKeys: String, CodingKey { case path = "Path" }
}

private struct UserResponse: Decodable {
    struct Policy: Decodable {
        let isAdministrator: Bool?
        let isDisabled: Bool?
        enum CodingKeys: String, CodingKey { case isAdministrator = "IsAdministrator", isDisabled = "IsDisabled" }
    }
    let id: String
    let name: String
    let hasPassword: Bool?
    let lastActivityDate: String?
    let primaryImageTag: String?
    let policy: Policy?
    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", hasPassword = "HasPassword", lastActivityDate = "LastActivityDate"
        case primaryImageTag = "PrimaryImageTag", policy = "Policy"
    }
}

private struct DevicesPage: Decodable {
    struct Device: Decodable {
        let id: String
        let name: String?
        let appName: String?
        let appVersion: String?
        let lastUserName: String?
        let dateLastActivity: String?
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", appName = "AppName", appVersion = "AppVersion"
            case lastUserName = "LastUserName", dateLastActivity = "DateLastActivity"
        }
    }
    let items: [Device]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct PluginResponse: Decodable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let status: String?
    let canUninstall: Bool?
    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", version = "Version", description = "Description", status = "Status"
        case canUninstall = "CanUninstall"
    }
}

private struct PackageResponse: Decodable {
    struct Version: Decodable {
        let version: String?
        let repositoryUrl: String?
    }
    let name: String
    let description: String?
    let overview: String?
    let category: String?
    let guid: String?
    let versions: [Version]?
}

private struct KeysPage: Decodable {
    struct Key: Decodable {
        let accessToken: String
        let appName: String?
        let dateCreated: String?
        enum CodingKeys: String, CodingKey { case accessToken = "AccessToken", appName = "AppName", dateCreated = "DateCreated" }
    }
    let items: [Key]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct LogFileResponse: Decodable {
    let name: String
    let size: Int64?
    let dateModified: String?
    enum CodingKeys: String, CodingKey { case name = "Name", size = "Size", dateModified = "DateModified" }
}

private struct BackupResponse: Decodable {
    let path: String
    let serverVersion: String?
    let dateCreated: String?
    enum CodingKeys: String, CodingKey { case path = "Path", serverVersion = "ServerVersion", dateCreated = "DateCreated" }
}
