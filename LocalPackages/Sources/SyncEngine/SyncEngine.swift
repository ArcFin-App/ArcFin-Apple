// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import Persistence
import SwiftData
import Telemetry

// MARK: - Offline playback progress sync

/// Pushes playback progress/watched-status recorded while offline back to each item's
/// server, using the standard Sessions/Playing/Stopped and PlayedItems endpoints — the same
/// ones the online player already reports through, just called after the fact instead of
/// live. Best-effort per item: a failure (server unreachable, item deleted server-side, that
/// server's profile no longer saved) leaves needsSync set for a later retry rather than
/// failing the whole batch.
public enum OfflineProgressSync {
    private static let log = Telemetry.logger(category: "OfflineProgressSync")

    @MainActor
    public static func syncPending(
        modelContext: ModelContext,
        profiles: [ServerCredential],
        authHeader: (ServerCredential) -> String
    ) async {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.needsSync })
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }

        let client = JellyfinMediaClient()
        var syncedCount = 0
        for item in pending {
            // serverId is the ServerCredential's own id (see DownloadManager, where it's
            // stored as credential.id.uuidString) — matched against currently saved profiles
            // rather than requiring the item's original server to still be the active one.
            guard let credential = profiles.first(where: {
                $0.id.uuidString == item.serverId && $0.userID == item.userId
            }) else { continue }

            let header = authHeader(credential)
            await client.reportPlaybackStopped(
                credential: credential, authHeader: header,
                itemId: item.itemId, mediaSourceId: item.itemId,
                positionTicks: item.playbackPositionTicks
            )
            if item.played {
                try? await client.markWatched(credential: credential, authHeader: header, itemId: item.itemId, watched: true)
            }
            item.needsSync = false
            syncedCount += 1
        }
        try? modelContext.save()
        if syncedCount > 0 {
            log.info("Synced \(syncedCount) offline-played item(s) back to their server")
        }
    }
}

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
