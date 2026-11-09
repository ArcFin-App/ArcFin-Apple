// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore
import JellyfinAPI

/// Signing another device in with Quick Connect, from Settings, under Your Profile.
@MainActor @Observable
final class QuickConnectModel {
    var code = ""
    private(set) var isAuthorizing = false
    private(set) var result: String?

    func authorize(authManager: AuthManager) {
        guard case .authenticated(let cred) = authManager.state else { return }
        isAuthorizing = true
        result = nil
        let code = code
        Task {
            let header = authManager.authClient.authHeader(token: cred.accessToken)
            do {
                let ok = try await authManager.authClient.authorizeQuickConnect(
                    baseURL: cred.baseURL, authHeader: header, code: code
                )
                result = ok ? "✓ Device authorized" : "✗ Invalid or expired code"
                if ok { self.code = "" }
            } catch {
                result = "✗ \(error.localizedDescription)"
            }
            isAuthorizing = false
        }
    }
}
