// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// MARK: - Season-level request state

/// Where a single season of a series stands, read the same way Seerr's own request table
/// reads it: the library first (unless it lost the season), then a request that still stands.
public enum SeerrSeasonBadge: Sendable, Equatable {
    case notRequested, pending, requested, partiallyAvailable, available
}

public struct SeerrSeasonRow: Sendable, Identifiable, Equatable {
    public var id: Int { seasonNumber }
    public let seasonNumber: Int
    public let episodeCount: Int
    /// nil in the odd cases Seerr shows none, such as a failed request with no library entry.
    public let badge: SeerrSeasonBadge?
    /// Already requested or already in the library — can't be toggled, and counts as part of
    /// a "whole series" request regardless of the selection below.
    public let locked: Bool

    public var label: String { seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)" }
}

/// A user's series request quota, from `GET /api/v1/user/{id}/quota`.
public struct SeerrSeasonQuota: Sendable, Equatable {
    public let limit: Int?
    public let remaining: Int?
    public let days: Int?
    public let restricted: Bool
}

public struct SeerrPublicSettings: Sendable, Equatable {
    /// False on a server configured to only ever request whole series — there is then
    /// nothing to choose, and a request always asks for every season left.
    public let partialRequestsEnabled: Bool
    public let enableSpecialEpisodes: Bool
}

// MARK: - Pure selection logic
//
// Ported from Seerr's own request modal (TvRequestModal: getAllSeasons,
// getAllRequestedSeasons, toggleSeason, toggleAllSeasons) so picking seasons here behaves the
// same as it does on Seerr's own site/web UI.

public enum SeerrSeasonSelection {
    /// The seasons that can still be requested — not already requested, not in the library.
    public static func unrequested(_ rows: [SeerrSeasonRow]) -> [Int] {
        rows.filter { !$0.locked }.map(\.seasonNumber)
    }

    /// Whether the quota leaves room to switch on one more season.
    public static func roomForOneMore(selected: Set<Int>, quota: SeerrSeasonQuota?) -> Bool {
        guard let limit = quota?.limit, limit > 0 else { return true }
        return (quota?.remaining ?? 0) - selected.count > 0
    }

    /// Whether the seasons switched on fit the quota. They can stop fitting once the quota
    /// changes under them (a request made elsewhere spends it); Seerr then refuses the whole
    /// request.
    public static func withinQuota(selected: Set<Int>, quota: SeerrSeasonQuota?) -> Bool {
        guard let limit = quota?.limit, limit > 0 else { return true }
        return selected.count <= (quota?.remaining ?? 0)
    }

    /// Whether the quota covers every season that can still be requested.
    public static func roomForAll(unrequested: [Int], quota: SeerrSeasonQuota?) -> Bool {
        guard let limit = quota?.limit, limit > 0 else { return true }
        return (quota?.remaining ?? 0) >= unrequested.count
    }

    /// Adds or removes a season, within what can be requested and the quota.
    public static func toggle(_ selected: Set<Int>, season: Int, unrequested: [Int], quota: SeerrSeasonQuota?) -> Set<Int> {
        guard unrequested.contains(season) else { return selected }
        if selected.contains(season) {
            var next = selected
            next.remove(season)
            return next
        }
        guard roomForOneMore(selected: selected, quota: quota) else { return selected }
        var next = selected
        next.insert(season)
        return next
    }

    /// Whether the "select all" control would select them, rather than clear them (true once
    /// at least one unrequested season isn't yet selected).
    public static func selectsAll(_ selected: Set<Int>, unrequested: [Int]) -> Bool {
        unrequested.contains { !selected.contains($0) }
    }

    /// Selects every season that can be requested, when the quota covers them all, or clears
    /// the selection once they all already are.
    public static func toggleAll(_ selected: Set<Int>, unrequested: [Int], quota: SeerrSeasonQuota?) -> Set<Int> {
        guard selectsAll(selected, unrequested: unrequested) else { return [] }
        return roomForAll(unrequested: unrequested, quota: quota) ? Set(unrequested) : selected
    }
}

// MARK: - Permission bitmask
//
// Ported from Jellyseerr/Overseerr's own `server/lib/permissions.ts` (MIT) — a stable,
// versioned protocol constant, not application logic that changes with this app's own needs.
// Only the bits this feature actually reads are included.

public struct SeerrPermission: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let admin = SeerrPermission(rawValue: 2)
    public static let manageRequests = SeerrPermission(rawValue: 16)
    public static let autoApprove = SeerrPermission(rawValue: 128)
    public static let autoApproveTV = SeerrPermission(rawValue: 512)

    /// True if the admin bit is set (which Seerr treats as "can do anything") or any of
    /// `permissions` is present in `value`.
    public static func hasAny(of permissions: [SeerrPermission], in value: Int) -> Bool {
        if value & SeerrPermission.admin.rawValue != 0 { return true }
        return permissions.contains { value & $0.rawValue != 0 }
    }
}

public struct SeerrCurrentUser: Sendable, Equatable {
    public let id: Int
    public let permissions: Int
}
