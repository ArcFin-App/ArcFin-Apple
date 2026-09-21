// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import AuthCore
import Telemetry

// MARK: - Client protocol
// Stub — replace with OpenAPI-generated types once streamystats openapi.yaml is wired up.

public protocol StreamystatsClientProtocol: Sendable {
    func getPlayHistory(serverID: UUID, userID: String, limit: Int) async throws -> [PlayHistoryEntry]
    func getTopMedia(serverID: UUID, userID: String, limit: Int) async throws -> [TopMediaEntry]
    func getWatchTimeStats(serverID: UUID, userID: String) async throws -> WatchTimeStats
    func getActivityHeatmap(serverID: UUID, userID: String) async throws -> [HeatmapEntry]
}

// MARK: - Stub models

public struct PlayHistoryEntry: Sendable, Identifiable, Equatable {
    public let id: String
    public var itemID: String
    public var itemName: String
    public var playedAt: Date
    public var durationSeconds: Int

    public init(id: String, itemID: String, itemName: String, playedAt: Date, durationSeconds: Int) {
        self.id = id
        self.itemID = itemID
        self.itemName = itemName
        self.playedAt = playedAt
        self.durationSeconds = durationSeconds
    }
}

public struct TopMediaEntry: Sendable, Identifiable, Equatable {
    public let id: String
    public var itemName: String
    public var playCount: Int
    public var totalWatchSeconds: Int

    public init(id: String, itemName: String, playCount: Int, totalWatchSeconds: Int) {
        self.id = id
        self.itemName = itemName
        self.playCount = playCount
        self.totalWatchSeconds = totalWatchSeconds
    }
}

public struct WatchTimeStats: Sendable, Equatable {
    public var totalSeconds: Int
    public var todaySeconds: Int
    public var weekSeconds: Int
    public var monthSeconds: Int

    public init(totalSeconds: Int, todaySeconds: Int, weekSeconds: Int, monthSeconds: Int) {
        self.totalSeconds = totalSeconds
        self.todaySeconds = todaySeconds
        self.weekSeconds = weekSeconds
        self.monthSeconds = monthSeconds
    }
}

public struct HeatmapEntry: Sendable, Equatable {
    public var date: Date
    public var watchSeconds: Int

    public init(date: Date, watchSeconds: Int) {
        self.date = date
        self.watchSeconds = watchSeconds
    }
}
