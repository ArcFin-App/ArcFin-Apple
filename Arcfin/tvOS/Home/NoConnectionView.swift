// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

struct NoConnectionView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var confirmSignOut = false

    var body: some View {
        NoConnectionContent(signOut: { confirmSignOut = true }) {}
            .confirmationDialog("Sign out of this server?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { authManager.signOut() }
            } message: {
                Text("You'll need to sign in again to use it. Downloads stay on this device.")
            }
    }
}

#Preview {
    NoConnectionView()
        .environment(AuthManager())
        .environment(MediaRepository())
}
