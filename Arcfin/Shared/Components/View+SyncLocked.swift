// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Disables a control when the admin has locked its setting key via the Arcfin Sync plugin.
    /// A no-op (never disables) when the plugin isn't installed — arcfinSyncLockedKeys stays
    /// empty in that case, see AuthManager.refreshArcfinSync. Also dims it — .disabled() alone
    /// blocks interaction but doesn't change how a plain TextField looks, so a locked field
    /// was functionally read-only while still looking fully editable.
    func syncLocked(_ key: String, _ authManager: AuthManager) -> some View {
        modifier(SyncLockedModifier(isLocked: authManager.arcfinSyncLockedKeys.contains(key)))
    }
}

/// A locked control says why underneath it. Only a locked row is wrapped, so an unlocked
/// one keeps its own list-row styling.
private struct SyncLockedModifier: ViewModifier {
    let isLocked: Bool

    func body(content: Content) -> some View {
        if isLocked {
            VStack(alignment: .leading, spacing: 4) {
                content
                    .disabled(true)
                    .opacity(0.5)
                Label("Set by your server's admin", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            content
        }
    }
}
