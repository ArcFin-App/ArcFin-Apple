import Foundation
import Telemetry

// MARK: - Sync client protocol

public protocol SyncClientProtocol: Sendable {
    func push(_ payload: SyncPayload) async throws
    func pull() async throws -> SyncPayload
    func resolveConflict(local: SyncPayload, remote: SyncPayload) -> SyncPayload
}

// MARK: - Sync payload

public struct SyncPayload: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var lastModified: Date
    public var settings: [String: String]

    public init(schemaVersion: Int = 1, lastModified: Date = .now, settings: [String: String] = [:]) {
        self.schemaVersion = schemaVersion
        self.lastModified = lastModified
        self.settings = settings
    }
}

// MARK: - Sync source priority

public enum SyncSource: Sendable {
    case jellyfinPlugin   // companion server plugin
    case cloudKit         // iCloud fallback
}

// MARK: - Conflict resolution strategy

public enum ConflictResolution: Sendable {
    case lastWriteWins
    case serverWins
    case clientWins
}
