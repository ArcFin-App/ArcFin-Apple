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
