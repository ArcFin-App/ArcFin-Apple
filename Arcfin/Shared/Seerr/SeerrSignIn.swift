// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import SeerrAPI

/// Connecting Seerr with the Jellyfin account through Quick Connect.
enum SeerrSignIn {
    /// Approves Seerr's Quick Connect code with whichever Jellyfin profile is signed in when
    /// Seerr asks, so a profile switch never approves it as the previous user.
    nonisolated static func quickConnectAuthorizer(authManager: AuthManager) -> SeerrHTTPClient.QuickConnectAuthorizer {
        { [weak authManager] code in
            guard let credential = await authManager?.state.credential else { return false }
            return try await quickConnectAuthorizer(credential: credential)(code)
        }
    }

    /// The same for work done without the app's state, such as a background refresh.
    nonisolated static func quickConnectAuthorizer(credential: ServerCredential) -> SeerrHTTPClient.QuickConnectAuthorizer {
        { code in
            let client = JellyfinAuthClient()
            return try await client.authorizeQuickConnect(
                baseURL: credential.baseURL, authHeader: client.authHeader(token: credential.accessToken), code: code)
        }
    }
}

/// What to tell someone when Seerr won't sign in.
enum SeerrSignInText {
    static func message(for error: Error) -> String {
        switch error as? SeerrError {
        case .authFailed:
            String(localized: "Seerr didn't accept that username or password.")
        case .quickConnectUnavailable(seerrTooOld: true):
            String(localized: "This version of Seerr can't connect with Quick Connect. Update Seerr, or enter your password instead.")
        case .quickConnectUnavailable(seerrTooOld: false):
            String(localized: "Quick Connect is turned off on your Jellyfin server. Ask your admin to turn it on, or enter your password instead.")
        case .quickConnectRefused(let reason?):
            reason
        case .quickConnectNotStarted:
            String(localized: "Seerr couldn't start a Quick Connect sign-in. Check that Seerr can reach your Jellyfin server, or enter your password instead.")
        case .quickConnectRefused(nil):
            String(localized: "Seerr didn't accept your Jellyfin account. Ask your admin to add you to Seerr.")
        case .requestFailed, nil:
            String(localized: "Couldn't reach Seerr. Check the address and your connection, then try again.")
        }
    }
}

/// Seerr wouldn't sign in: says so, with Try Again, where a Seerr list would be.
struct SeerrSignInFailedView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @State private var isRetrying = false

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Sign In to Seerr", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            SeerrSettingsHint.signInFailed
        } actions: {
            Button {
                isRetrying = true
                Task {
                    await seerrRepo.retrySignIn()
                    isRetrying = false
                }
            } label: {
                if isRetrying { ProgressView() } else { Text("Try Again") }
            }
            .buttonStyle(.borderedProminent)
            .tint(DT.Color.accent)
            .disabled(isRetrying)
        }
    }
}
