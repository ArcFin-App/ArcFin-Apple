// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Whether this platform has the admin screens; Apple TV has none.
enum AdminPlatform {
    static let isAvailable = true
}

extension AdminPlatform {
    /// Arcs is only on iPhone and iPad, so it's set up there.
    static func arcsAdminLink(users: [ArcfinSyncAdminUser]) -> some View { EmptyView() }
}
