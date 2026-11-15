// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

/// The version and build Settings › About shows.
enum AppBuild {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    static var number: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

/// The line under Settings › About.
struct MadeByFooter: View {
    var body: some View {
        // A footer, not a row — an extra row with a cleared background broke the
        // section's rounded-corner silhouette at the bottom edge (a List quirk: the
        // last row's background normally supplies that corner).
        Text("Made by PSMattas")
            .font(.system(.caption2, design: .default, weight: .semibold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(DT.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }
}

/// Settings' last section: signing out of the current profile, after asking.
struct SignOutSection: View {
    @Environment(AuthManager.self) private var authManager
    @State private var signOutTarget: ServerCredential?

    var body: some View {
        Section {
            Button(role: .destructive) {
                signOutTarget = authManager.state.credential
            } label: {
                Text("Sign Out")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .formRowButton()
        }
        .confirmingProfileRemoval($signOutTarget, signingOut: true,
                                  isLastProfile: authManager.profiles.count <= 1) { _ in
            authManager.signOut()
        }
    }
}
