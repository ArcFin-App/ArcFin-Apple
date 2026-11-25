// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import SeerrAPI

@Suite("Seerr issues")
struct SeerrIssueTests {
    private let json = Data("""
    {"id": 12, "issueType": 3, "status": 1, "problemSeason": 2, "problemEpisode": 0,
     "createdAt": "2026-11-25T07:52:16.000Z", "updatedAt": "2026-11-25T08:01:00Z",
     "createdBy": {"id": 4, "displayName": "Sam", "jellyfinUserId": "abc"},
     "media": {"id": 88, "tmdbId": 1399, "mediaType": "tv", "status": 5},
     "comments": [
        {"id": 31, "message": "Fixed?", "user": {"id": 1, "displayName": "Admin"}, "createdAt": "2026-11-25T08:00:00.000Z"},
        {"id": 30, "message": "Subtitles are out of sync", "user": {"id": 4, "displayName": "Sam"}, "createdAt": "2026-11-25T07:52:16.000Z"}
     ]}
    """.utf8)

    @Test("An issue decodes, with comments oldest first and episode 0 meaning the whole season")
    func decodesAnIssue() throws {
        let issue = try JSONDecoder().decode(SeerrIssueResponse.self, from: json).toIssue()
        #expect(issue.id == 12)
        #expect(issue.type == .subtitles)
        #expect(issue.status == .open)
        #expect(issue.problemSeason == 2)
        #expect(issue.problemEpisode == nil)
        #expect(issue.createdBy == SeerrIssueUser(id: 4, name: "Sam"))
        #expect(issue.mediaID == 88 && issue.tmdbId == 1399 && issue.mediaType == .tv)
        #expect(issue.comments.map(\.id) == [30, 31])
        #expect(issue.comments.first?.message == "Subtitles are out of sync")
        #expect(issue.createdAt != nil && issue.updatedAt != nil)
    }

    @Test("Missing fields fall back instead of failing")
    func decodesSparseIssues() throws {
        let issue = try JSONDecoder().decode(SeerrIssueResponse.self, from: Data(#"{"id": 3}"#.utf8)).toIssue()
        #expect(issue.type == .other && issue.status == .open && issue.comments.isEmpty && issue.createdBy == nil)
    }

    @Test("Permissions: create, view everyone's, manage; admin can do all")
    func permissions() {
        let reporter = SeerrIssuePermissions(userID: 4, permissions: SeerrPermission.createIssues.rawValue)
        #expect(reporter.canCreate && !reporter.canViewAll && !reporter.canManage)
        let viewer = SeerrIssuePermissions(userID: 5, permissions: SeerrPermission.viewIssues.rawValue)
        #expect(!viewer.canCreate && viewer.canViewAll && !viewer.canManage)
        let manager = SeerrIssuePermissions(userID: 6, permissions: SeerrPermission.manageIssues.rawValue)
        #expect(manager.canCreate && manager.canViewAll && manager.canManage)
        let admin = SeerrIssuePermissions(userID: 1, permissions: SeerrPermission.admin.rawValue)
        #expect(admin.canCreate && admin.canViewAll && admin.canManage)
        #expect(!SeerrIssuePermissions.none.canCreate)
    }

    @Test("The reporter may change their own issue; others need Manage Issues")
    func changingAnIssue() {
        let issue = SeerrIssue(id: 1, type: .video, status: .open, createdBy: SeerrIssueUser(id: 4, name: "Sam"))
        #expect(SeerrIssuePermissions(userID: 4, permissions: 0).canChange(issue))
        #expect(!SeerrIssuePermissions(userID: 5, permissions: SeerrPermission.viewIssues.rawValue).canChange(issue))
        #expect(SeerrIssuePermissions(userID: 5, permissions: SeerrPermission.manageIssues.rawValue).canChange(issue))
    }
}
