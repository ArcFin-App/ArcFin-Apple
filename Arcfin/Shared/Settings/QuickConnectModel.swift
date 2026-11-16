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

/// The link in the Apple TV's Quick Connect QR code. It's a link on Arcfin's website, so the
/// Camera opens it in Arcfin where it's installed. Where it isn't, the page shows the code and
/// a way to the server's own Quick Connect page. The code and server are in the fragment,
/// which a browser never sends, so they never reach the website.
enum QuickConnectLink {
    static let host = "arcfin.psmattas.com"
    static let path = "/quickconnect"

    static func url(server: URL, code: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = path + "/"
        var fragment = URLComponents()
        fragment.queryItems = [.init(name: "server", value: server.absoluteString), .init(name: "code", value: code)]
        comps.percentEncodedFragment = fragment.percentEncodedQuery
        return comps.url
    }

    static func parse(_ url: URL) -> (server: URL?, code: String)? {
        guard url.scheme == "https", url.host == host, url.path == path || url.path == path + "/",
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
              let items = { var f = URLComponents(); f.percentEncodedQuery = fragment; return f.queryItems }(),
              let code = items.first(where: { $0.name == "code" })?.value?.filter(\.isNumber), !code.isEmpty
        else { return nil }
        return (items.first(where: { $0.name == "server" })?.value.flatMap(URL.init(string:)), code)
    }
}

/// A Quick Connect code from a scanned QR code, waiting for "Sign in the Apple TV?".
@MainActor @Observable
final class QuickConnectApproval {
    static let shared = QuickConnectApproval()

    struct Request: Identifiable, Equatable {
        let id = UUID()
        let code: String
        let server: URL?
    }

    struct Outcome: Identifiable, Equatable {
        let id = UUID()
        let succeeded: Bool
        let message: String
    }

    var request: Request?
    var outcome: Outcome?
    private(set) var isApproving = false

    func open(_ url: URL) -> Bool {
        guard let link = QuickConnectLink.parse(url) else { return false }
        request = Request(code: link.code, server: link.server)
        return true
    }

    /// The code is approved on this profile's server. One from another server isn't known
    /// there, so it fails without signing anything in.
    func approve(_ request: Request, authManager: AuthManager) {
        guard let credential = authManager.state.credential else {
            outcome = Outcome(succeeded: false, message: String(localized: "Sign in to Arcfin on this device first, then scan the code again."))
            return
        }
        isApproving = true
        Task {
            let header = authManager.authClient.authHeader(token: credential.accessToken)
            let approved = (try? await authManager.authClient.authorizeQuickConnect(
                baseURL: credential.baseURL, authHeader: header, code: request.code)) ?? false
            isApproving = false
            if approved {
                outcome = Outcome(succeeded: true, message: String(localized: "The Apple TV is signing in as \(credential.displayName)."))
            } else if let server = request.server, server.host != credential.baseURL.host {
                outcome = Outcome(succeeded: false, message: String(localized: "This code is for \(server.host ?? server.absoluteString), but this device is signed in to \(credential.baseURL.host ?? credential.baseURL.absoluteString). Sign in to that server here, or type the code on a device that is."))
            } else {
                outcome = Outcome(succeeded: false, message: String(localized: "The code has expired or was already used. Get a new code on the Apple TV and scan it again."))
            }
        }
    }
}
