// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

struct NoConnectionView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var confirmSignOut = false

    var body: some View {
        NoConnectionContent(networkTips: [String(localized: "Check that this Apple TV is connected in Settings › Network")], signOut: { confirmSignOut = true }) {}
            .alert("Sign out of this server?", isPresented: $confirmSignOut) {
                Button("Sign Out", role: .destructive) { authManager.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to use it.")
            }
    }
}

#Preview {
    NoConnectionView()
        .environment(AuthManager())
        .environment(MediaRepository())
}
