// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Disables a control when the admin has locked its setting key via the Arcfin Sync plugin.
    /// A no-op (never disables) when the plugin isn't installed — arcfinSyncLockedKeys stays
    /// empty in that case, see AuthManager.refreshArcfinSync.
    func syncLocked(_ key: String, _ authManager: AuthManager) -> some View {
        disabled(authManager.arcfinSyncLockedKeys.contains(key))
    }
}
