// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Whether this platform has the admin screens; Apple TV has none.
enum AdminPlatform {
    static let isAvailable = true
}

extension AdminPlatform {
    /// Arcfin for Everyone › Arcs: who has it, what it picks from, sharing and the clip cache.
    @MainActor static func arcsAdminLink(users: [ArcfinSyncAdminUser]) -> some View {
        NavigationLink {
            ArcsAdminView(users: users)
        } label: {
            TVRowLabelText(title: "Arcs", detail: "Who has it, what it shows, sharing and recommendations")
        }
    }
}
