// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore
import Telemetry
import Network
// Needed for the privacy-annotated string interpolation in the error log below — Telemetry
// wraps os.Logger, but that doesn't re-export the OSLogMessage interpolation machinery to
// callers (see MediaRepository.swift, which hit the identical "missing import of defining
// module 'os'" compile error for the same reason).
import os
#if canImport(UIKit)
import UIKit
#endif

/// Races a one-shot NWPathMonitor read against a timeout — same lock-guarded resume-once
/// pattern as MediaRepository's PathWait (duplicated rather than shared across the module
/// boundary, small enough not to be worth a cross-package refactor for now).
private final class PathWait: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Void, Never>
    private let monitor = NWPathMonitor()

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func start(timeoutSeconds: Double) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            self?.finish()
        }
        monitor.start(queue: DispatchQueue(label: "arcfin.jellyfinauth.pathwait"))
        Task {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            self.finish()
        }
    }

    private func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        monitor.cancel()
        continuation.resume()
    }
}

// MARK: - Errors

public enum JellyfinAuthError: Error, LocalizedError, Sendable {
    case invalidServerURL
    case serverUnreachable
    case authFailed(String)
    case invalidResponse
    /// A 401/403 from QuickConnect/Initiate — the server actively rejected the request,
    /// e.g. Quick Connect really is turned off in Dashboard > General.
    case quickConnectDisabled
    /// Any other non-200 from QuickConnect/Initiate. `quickConnectUnavailable` used to be
    /// thrown for this whole category with a hardcoded "not enabled" message regardless of
    /// the real cause (wrong path, a proxy/gateway error page, a genuine server error) —
    /// actively misleading when the real cause was something else. Carries the real status
    /// code so it's at least honest about what actually happened.
    case quickConnectFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:       return "Invalid server URL."
        case .serverUnreachable:      return "Cannot reach server — check the address and try again."
        case .authFailed(let msg):    return msg
        case .invalidResponse:        return "Unexpected server response."
        case .quickConnectDisabled:   return "Quick Connect is not enabled on this server."
        case .quickConnectFailed(let statusCode):
            return "Quick Connect request failed (server returned HTTP \(statusCode)). If Quick Connect is enabled in Dashboard > General, check the server URL and try again."
        }
    }
}

// MARK: - Response models (private)

private struct PublicInfo: Decodable {
    let id: String
    let serverName: String
    enum CodingKeys: String, CodingKey {
        case id = "Id"; case serverName = "ServerName"
    }
}

private struct AuthResponse: Decodable {
    let accessToken: String
    let serverId: String
    let user: UserInfo
    struct UserInfo: Decodable {
        let id: String
        let name: String
        let primaryImageTag: String?
        enum CodingKeys: String, CodingKey {
            case id = "Id"; case name = "Name"; case primaryImageTag = "PrimaryImageTag"
        }
    }
    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"; case serverId = "ServerId"; case user = "User"
    }
}

private struct QCInitResponse: Decodable {
    let secret: String
    let code: String
    enum CodingKeys: String, CodingKey { case secret = "Secret"; case code = "Code" }
}

private struct QCStatusResponse: Decodable {
    let authenticated: Bool
    enum CodingKeys: String, CodingKey { case authenticated = "Authenticated" }
}

// MARK: - Client

public struct JellyfinAuthClient: Sendable {

    public static let appVersion = "0.0.1"
    private static let log = Telemetry.logger(category: "JellyfinAuth")

    private let deviceId: String
    private let deviceName: String

    /// Keeps the MediaBrowser auth header's Device="..." field to plain, printable ASCII
    /// with no double quotes or backslashes — those would break the quoted-string field
    /// outright, and there's no guarantee every Jellyfin server (or a reverse proxy in
    /// front of one) parses that header as strictly/leniently as another. A name that's
    /// empty after stripping falls back to a safe default rather than sending Device="".
    private static func sanitize(_ name: String) -> String {
        let cleaned = String(name.unicodeScalars.filter { scalar in
            scalar.isASCII && scalar.value >= 0x20 && scalar != "\"" && scalar != "\\"
        })
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Arcfin" : trimmed
    }

    public init() {
        let key = "arcfin.deviceId"
        if let stored = UserDefaults.standard.string(forKey: key) {
            deviceId = stored
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: key)
            deviceId = id
        }
        let rawName: String
        #if os(iOS) || os(tvOS)
        // UIDevice is main-actor only, and assumeIsolated traps anywhere else. This client is
        // also created by Siri / Spotlight intents on a background thread, so the name is
        // remembered whenever it can be read and reused when it can't.
        let cachedNameKey = "arcfin.cachedDeviceName"
        if Thread.isMainThread {
            rawName = MainActor.assumeIsolated { UIDevice.current.name }
            UserDefaults.standard.set(rawName, forKey: cachedNameKey)
        } else {
            rawName = UserDefaults.standard.string(forKey: cachedNameKey) ?? "Arcfin"
        }
        #elseif os(macOS)
        // Host.current().localizedName is the user-editable "Computer Name" from System
        // Settings > Sharing — unlike UIDevice's iOS device name, this can contain
        // non-ASCII characters (emoji, accents) a naive server-side auth-header parser may
        // not expect inside the quoted Device="..." field, which reads to the server as a
        // malformed header (400 Bad Request) rather than an auth failure. Sanitized below,
        // same as deviceName always is now regardless of platform.
        rawName = Host.current().localizedName ?? "Mac"
        #else
        rawName = "Arcfin"
        #endif
        deviceName = Self.sanitize(rawName)
    }

    // MARK: - Server validation

    /// Normalises the raw URL string, contacts /System/Info/Public, returns (URL, serverName).
    ///
    /// A bare host:port — the natural way to type a local server's address — has no scheme
    /// to go on. Silently defaulting that to HTTPS alone broke every plain-HTTP local
    /// Jellyfin instance (the common case: most LAN setups have no TLS cert at all), and the
    /// resulting TLS handshake failure collapsed into the same generic "Cannot reach server"
    /// message with nothing to tell it apart from a genuinely offline server. An address
    /// typed WITH an explicit scheme is trusted exactly as given, no fallback; one without
    /// tries HTTPS first (so a real TLS server still connects on the first attempt) and only
    /// falls back to HTTP if that fails.
    public func validateServer(url rawURL: String) async throws -> (url: URL, serverName: String) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JellyfinAuthError.invalidServerURL }

        let candidates: [URL]
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard let url = normalise(trimmed) else { throw JellyfinAuthError.invalidServerURL }
            candidates = [url]
        } else {
            guard let httpsURL = normalise("https://" + trimmed),
                  let httpURL = normalise("http://" + trimmed)
            else { throw JellyfinAuthError.invalidServerURL }
            candidates = [httpsURL, httpURL]
        }

        // This is typically the very first network request the app ever makes (server
        // setup screen, right after a fresh install/cold launch) — exactly when iOS/macOS's
        // local-network authorization can still transiently report the path as prohibited
        // even though the permission is already granted, until its own cache settles (the
        // same condition confirmed by NWPathKey=unsatisfied "Local network prohibited" logs
        // elsewhere in this app). Waiting for a satisfied path first, bounded so a genuinely
        // offline server still fails promptly, avoids losing that race on the very first try.
        await Self.waitForNetworkPath()

        var lastError: Error = JellyfinAuthError.serverUnreachable
        for base in candidates {
            do {
                return try await fetchPublicInfo(base: base)
            } catch {
                lastError = error
            }
        }
        // Whichever candidate failed last is the one worth logging — the real reason
        // ("Cannot reach server" was previously the ONLY thing ever surfaced, regardless of
        // whether the cause was a bad cert, DNS failure, wrong port, or an offline server).
        let nsError = lastError as NSError
        Self.log.error(
            "validateServer failed for \(trimmed, privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
        )
        throw JellyfinAuthError.serverUnreachable
    }

    private static func waitForNetworkPath(timeoutSeconds: Double = 6) async {
        await withCheckedContinuation { continuation in
            PathWait(continuation: continuation).start(timeoutSeconds: timeoutSeconds)
        }
    }

    private func fetchPublicInfo(base: URL) async throws -> (url: URL, serverName: String) {
        var req = URLRequest(url: base.appendingPathComponent("System/Info/Public"))
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw JellyfinAuthError.serverUnreachable
        }
        let info = try JSONDecoder().decode(PublicInfo.self, from: data)
        return (Self.base(answering: resp, requested: base), info.serverName)
    }

    /// The address the server actually answered from. A proxy that redirects http:// to
    /// https:// (or adds a path) works for these requests, which follow redirects, but not
    /// for the players, downloads or the WebSocket, so the redirected address is the one saved.
    static func base(answering response: URLResponse, requested: URL) -> URL {
        let suffix = "/System/Info/Public"
        guard let final = response.url,
              var parts = URLComponents(url: final, resolvingAgainstBaseURL: false),
              parts.percentEncodedPath.hasSuffix(suffix)
        else { return requested }
        parts.percentEncodedPath = String(parts.percentEncodedPath.dropLast(suffix.count))
        parts.query = nil
        parts.fragment = nil
        return parts.url ?? requested
    }

    // MARK: - Password auth

    public func authenticate(baseURL: URL, username: String, password: String) async throws -> ServerCredential {
        var req = URLRequest(url: baseURL.appendingPathComponent("Users/AuthenticateByName"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        req.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])

        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw JellyfinAuthError.invalidResponse }
        guard http.statusCode == 200 else {
            let msg = http.statusCode == 401 ? "Invalid username or password." : "Sign-in failed (HTTP \(http.statusCode))."
            throw JellyfinAuthError.authFailed(msg)
        }
        let result = try JSONDecoder().decode(AuthResponse.self, from: data)
        return ServerCredential(baseURL: baseURL, userID: result.user.id,
                                accessToken: result.accessToken, displayName: result.user.name,
                                userImageTag: result.user.primaryImageTag)
    }

    // MARK: - Quick Connect

    public func initiateQuickConnect(baseURL: URL) async throws -> (code: String, secret: String) {
        var req = URLRequest(url: baseURL.appendingPathComponent("QuickConnect/Initiate"))
        req.httpMethod = "POST"
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let httpResp = resp as? HTTPURLResponse else { throw JellyfinAuthError.invalidResponse }
        guard httpResp.statusCode == 200 else {
            if httpResp.statusCode == 401 || httpResp.statusCode == 403 {
                throw JellyfinAuthError.quickConnectDisabled
            }
            throw JellyfinAuthError.quickConnectFailed(statusCode: httpResp.statusCode)
        }
        let result = try JSONDecoder().decode(QCInitResponse.self, from: data)
        return (result.code, result.secret)
    }

    public func pollQuickConnect(baseURL: URL, secret: String) async throws -> Bool {
        var comps = URLComponents(url: baseURL.appendingPathComponent("QuickConnect/Connect"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "Secret", value: secret)]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return (try? JSONDecoder().decode(QCStatusResponse.self, from: data))?.authenticated ?? false
    }

    public func authenticateWithQuickConnect(baseURL: URL, secret: String) async throws -> ServerCredential {
        var req = URLRequest(url: baseURL.appendingPathComponent("Users/AuthenticateWithQuickConnect"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        req.httpBody = try JSONEncoder().encode(["Secret": secret])

        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw JellyfinAuthError.invalidResponse }
        guard http.statusCode == 200 else { throw JellyfinAuthError.authFailed("Quick Connect auth failed.") }
        let result = try JSONDecoder().decode(AuthResponse.self, from: data)
        return ServerCredential(baseURL: baseURL, userID: result.user.id,
                                accessToken: result.accessToken, displayName: result.user.name,
                                userImageTag: result.user.primaryImageTag)
    }

    /// Authorizes a Quick Connect code shown on another, currently-signing-in device,
    /// using this session's own credentials. Distinct from initiateQuickConnect/pollQuickConnect
    /// above, which are the unauthenticated-device side of the same flow.
    public func authorizeQuickConnect(baseURL: URL, authHeader header: String, code: String) async throws -> Bool {
        var comps = URLComponents(url: baseURL.appendingPathComponent("QuickConnect/Authorize"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "Code", value: code)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(header, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw JellyfinAuthError.authFailed("Couldn't authorize that code.")
        }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? true
    }

    // MARK: - Token validation

    public func validateToken(credential: ServerCredential) async -> Bool {
        // Use an authenticated endpoint so an expired/revoked token returns 401, not 200.
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)"))
        req.setValue(authHeader(token: credential.accessToken), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        guard let (_, resp) = try? await URLSession.arcfin.data(for: req) else {
            // Request failed outright (offline, unreachable server) — don't force a
            // logout over a transient connectivity issue, only over a rejected token.
            return true
        }
        guard let http = resp as? HTTPURLResponse else { return true }
        return http.statusCode != 401 && http.statusCode != 403
    }

    /// Refreshes just the avatar tag for an already-authenticated credential — used to pick
    /// up a server-side avatar change (or backfill it for a credential saved before this
    /// field existed) without forcing a fresh sign-in.
    public func fetchUserImageTag(credential: ServerCredential) async -> String? {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)"))
        req.setValue(authHeader(token: credential.accessToken), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        struct UserResp: Decodable {
            let primaryImageTag: String?
            enum CodingKeys: String, CodingKey { case primaryImageTag = "PrimaryImageTag" }
        }
        return (try? JSONDecoder().decode(UserResp.self, from: data))?.primaryImageTag
    }

    /// Whether this credential's user has server admin rights — gates the Active Sessions
    /// screen. Not persisted on ServerCredential itself (keeps the keychain-stored shape
    /// stable); callers re-check this once per sign-in/app-launch instead.
    public func fetchIsAdministrator(credential: ServerCredential) async -> Bool {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)"))
        req.setValue(authHeader(token: credential.accessToken), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200
        else { return false }
        struct UserResp: Decodable {
            struct Policy: Decodable {
                let isAdministrator: Bool
                enum CodingKeys: String, CodingKey { case isAdministrator = "IsAdministrator" }
            }
            let policy: Policy?
            enum CodingKeys: String, CodingKey { case policy = "Policy" }
        }
        return (try? JSONDecoder().decode(UserResp.self, from: data))?.policy?.isAdministrator ?? false
    }

    // MARK: - Helpers

    public func authHeader(token: String? = nil) -> String {
        var parts = [
            "Client=\"Arcfin\"",
            "Device=\"\(deviceName)\"",
            "DeviceId=\"\(deviceId)\"",
            "Version=\"\(Self.appVersion)\"",
        ]
        if let t = token { parts.append("Token=\"\(t)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private func normalise(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "https://" + s }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return URL(string: s)
    }
}
