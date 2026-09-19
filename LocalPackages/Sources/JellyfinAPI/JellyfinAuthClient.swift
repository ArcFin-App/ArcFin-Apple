import Foundation
import AuthCore
import Telemetry
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Errors

public enum JellyfinAuthError: Error, LocalizedError, Sendable {
    case invalidServerURL
    case serverUnreachable
    case authFailed(String)
    case invalidResponse
    case quickConnectUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:       return "Invalid server URL."
        case .serverUnreachable:      return "Cannot reach server — check the address and try again."
        case .authFailed(let msg):    return msg
        case .invalidResponse:        return "Unexpected server response."
        case .quickConnectUnavailable: return "Quick Connect is not enabled on this server."
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

    public init() {
        let key = "arcfin.deviceId"
        if let stored = UserDefaults.standard.string(forKey: key) {
            deviceId = stored
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: key)
            deviceId = id
        }
        #if os(iOS) || os(tvOS)
        deviceName = MainActor.assumeIsolated { UIDevice.current.name }
        #elseif os(macOS)
        deviceName = Host.current().localizedName ?? "Mac"
        #else
        deviceName = "Arcfin"
        #endif
    }

    // MARK: - Server validation

    /// Normalises the raw URL string, contacts /System/Info/Public, returns (URL, serverName).
    public func validateServer(url rawURL: String) async throws -> (url: URL, serverName: String) {
        guard let base = normalise(rawURL) else { throw JellyfinAuthError.invalidServerURL }
        var req = URLRequest(url: base.appendingPathComponent("System/Info/Public"))
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw JellyfinAuthError.serverUnreachable
            }
            let info = try JSONDecoder().decode(PublicInfo.self, from: data)
            return (base, info.serverName)
        } catch let e as JellyfinAuthError { throw e }
        catch { throw JellyfinAuthError.serverUnreachable }
    }

    // MARK: - Password auth

    public func authenticate(baseURL: URL, username: String, password: String) async throws -> ServerCredential {
        var req = URLRequest(url: baseURL.appendingPathComponent("Users/AuthenticateByName"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        req.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw JellyfinAuthError.quickConnectUnavailable
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else {
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
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
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
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
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
