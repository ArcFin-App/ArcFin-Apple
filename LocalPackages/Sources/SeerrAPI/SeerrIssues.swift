// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What a Seerr issue is about, numbered as Seerr stores it.
public enum SeerrIssueType: Int, Sendable, CaseIterable, Identifiable, Hashable {
    case video = 1, audio, subtitles, other
    public var id: Int { rawValue }
}

public enum SeerrIssueStatus: Int, Sendable, Hashable {
    case open = 1, resolved
}

public enum SeerrIssueFilter: String, Sendable, CaseIterable, Hashable {
    case open, resolved, all
}

public struct SeerrIssueUser: Sendable, Equatable, Hashable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct SeerrIssueComment: Sendable, Identifiable, Equatable, Hashable {
    public let id: Int
    public let message: String
    public let user: SeerrIssueUser?
    public let createdAt: Date?

    public init(id: Int, message: String, user: SeerrIssueUser?, createdAt: Date?) {
        self.id = id
        self.message = message
        self.user = user
        self.createdAt = createdAt
    }
}

public struct SeerrIssue: Sendable, Identifiable, Equatable, Hashable {
    public let id: Int
    public let type: SeerrIssueType
    public let status: SeerrIssueStatus
    /// Nil or 0 in Seerr means the whole show, or every episode of the season.
    public let problemSeason: Int?
    public let problemEpisode: Int?
    public let createdBy: SeerrIssueUser?
    public let tmdbId: Int?
    public let mediaType: RequestMediaType?
    /// Seerr's own id for the title, which reporting an issue needs.
    public let mediaID: Int?
    /// Oldest first; the first is the reporter's own description. Lists leave them out.
    public let comments: [SeerrIssueComment]
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(id: Int, type: SeerrIssueType, status: SeerrIssueStatus, problemSeason: Int? = nil, problemEpisode: Int? = nil,
                createdBy: SeerrIssueUser? = nil, tmdbId: Int? = nil, mediaType: RequestMediaType? = nil, mediaID: Int? = nil,
                comments: [SeerrIssueComment] = [], createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.type = type
        self.status = status
        self.problemSeason = problemSeason
        self.problemEpisode = problemEpisode
        self.createdBy = createdBy
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.mediaID = mediaID
        self.comments = comments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isOpen: Bool { status == .open }
}

/// A title as Seerr knows it: its own id, needed to report an issue, and the issues on it.
public struct SeerrTitleIssues: Sendable, Equatable {
    public let mediaID: Int?
    public let issues: [SeerrIssue]

    public init(mediaID: Int?, issues: [SeerrIssue]) {
        self.mediaID = mediaID
        self.issues = issues
    }
}

/// What the signed-in Seerr user may do with issues. Seerr shows everyone their own issues; with
/// View Issues, everyone's. The reporter may also comment on, close, reopen and delete their own.
public struct SeerrIssuePermissions: Sendable, Equatable {
    public let userID: Int?
    public let canCreate: Bool
    public let canViewAll: Bool
    public let canManage: Bool

    public init(userID: Int?, permissions: Int) {
        self.userID = userID
        canCreate = SeerrPermission.hasAny(of: [.createIssues, .manageIssues], in: permissions)
        canViewAll = SeerrPermission.hasAny(of: [.viewIssues, .manageIssues], in: permissions)
        canManage = SeerrPermission.hasAny(of: [.manageIssues], in: permissions)
    }

    public static let none = SeerrIssuePermissions(userID: nil, permissions: 0)

    public func canChange(_ issue: SeerrIssue) -> Bool {
        canManage || (userID != nil && issue.createdBy?.id == userID)
    }
}

// MARK: - Decoding

struct SeerrIssueResponse: Decodable {
    let id: Int
    let issueType: Int?
    let status: Int?
    let problemSeason: Int?
    let problemEpisode: Int?
    let createdBy: UserResponse?
    let media: MediaResponse?
    let comments: [CommentResponse]?
    let createdAt: String?
    let updatedAt: String?

    struct UserResponse: Decodable {
        let id: Int
        let displayName: String?
        let username: String?
        let jellyfinUsername: String?
        let email: String?

        var user: SeerrIssueUser {
            SeerrIssueUser(id: id, name: [displayName, jellyfinUsername, username].compactMap { $0 }.first { !$0.isEmpty } ?? email ?? "")
        }
    }

    struct MediaResponse: Decodable {
        let id: Int?
        let tmdbId: Int?
        let mediaType: String?
    }

    struct CommentResponse: Decodable {
        let id: Int
        let message: String?
        let user: UserResponse?
        let createdAt: String?
    }

    func toIssue(media fallback: MediaResponse? = nil) -> SeerrIssue {
        let media = self.media ?? fallback
        return SeerrIssue(
            id: id,
            type: issueType.flatMap(SeerrIssueType.init(rawValue:)) ?? .other,
            status: status.flatMap(SeerrIssueStatus.init(rawValue:)) ?? .open,
            problemSeason: problemSeason.flatMap { $0 > 0 ? $0 : nil },
            problemEpisode: problemEpisode.flatMap { $0 > 0 ? $0 : nil },
            createdBy: createdBy?.user,
            tmdbId: media?.tmdbId,
            mediaType: media?.mediaType.flatMap(RequestMediaType.init(rawValue:)),
            mediaID: media?.id,
            comments: (comments ?? [])
                .map { SeerrIssueComment(id: $0.id, message: $0.message ?? "", user: $0.user?.user, createdAt: SeerrDates.parse($0.createdAt)) }
                .sorted { $0.id < $1.id },
            createdAt: SeerrDates.parse(createdAt),
            updatedAt: SeerrDates.parse(updatedAt))
    }
}

enum SeerrDates {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
