// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore
import JellyfinAPI
import SeerrAPI

/// Connecting Seerr with the Jellyfin account through Quick Connect.
enum SeerrSignIn {
    /// Approves Seerr's Quick Connect code with whichever Jellyfin profile is signed in when
    /// Seerr asks, so a profile switch never approves it as the previous user.
    static func quickConnectAuthorizer(authManager: AuthManager) -> SeerrHTTPClient.QuickConnectAuthorizer {
        { @MainActor [weak authManager] code in
            guard let authManager, case .authenticated(let credential) = authManager.state else { return false }
            let header = authManager.authClient.authHeader(token: credential.accessToken)
            return try await authManager.authClient.authorizeQuickConnect(
                baseURL: credential.baseURL, authHeader: header, code: code)
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
        case .quickConnectRefused(nil):
            String(localized: "Seerr didn't accept your Jellyfin account. Ask your admin to add you to Seerr.")
        case .requestFailed, nil:
            String(localized: "Couldn't reach Seerr. Check the address and your connection, then try again.")
        }
    }
}
