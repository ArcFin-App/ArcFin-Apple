// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

struct NoConnectionView: View {
    @Environment(AuthManager.self) private var authManager

    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    @State private var showSwitchServer = false
    @State private var confirmSignOut = false

    var body: some View {
        NoConnectionContent(signOut: { confirmSignOut = true }) {
            Button {
                offlineModeEnabled = true
            } label: {
                Text("Turn On Offline Mode")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .frame(maxWidth: 340)
                    .frame(height: 48)
                    .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.md))
            }

            // A way out when the server is gone for good: another saved server,
            // or back to sign-in.
            Button { showSwitchServer = true } label: {
                Text("Switch Server")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                    .frame(minHeight: 44)
            }
        }
        .sheet(isPresented: $showSwitchServer) {
            NavigationStack { SwitchServerView() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Sign out of this server?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { authManager.signOut() }
            Button("Cancel", role: .cancel) {}
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
