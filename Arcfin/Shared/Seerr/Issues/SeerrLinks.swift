// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Where a notification tap sends Discover, kept for a cold launch until Discover is up.
enum SeerrLinks {
    static let pendingRequestsKey = "arcfin.pendingSeerrRequests"
    static let pendingIssueKey = "arcfin.pendingSeerrIssue"
}

struct SeerrIssueLink: Identifiable, Hashable {
    let id: Int
}
