// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Disables a control when the admin has locked its setting key via the Arcfin Sync plugin.
    /// A no-op (never disables) when the plugin isn't installed — arcfinSyncLockedKeys stays
    /// empty in that case, see AuthManager.refreshArcfinSync. Also dims it — .disabled() alone
    /// blocks interaction but doesn't change how a plain TextField looks, so a locked field
    /// was functionally read-only while still looking fully editable.
    func syncLocked(_ key: String, _ authManager: AuthManager) -> some View {
        let isLocked = authManager.arcfinSyncLockedKeys.contains(key)
        return disabled(isLocked).opacity(isLocked ? 0.5 : 1.0)
    }
}
