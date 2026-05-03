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
        enum CodingKeys: String, CodingKey { case id = "Id"; case name = "Name" }
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

    public init() {
        let key = "arcfin.deviceId"
        if let stored = UserDefaults.standard.string(forKey: key) {
            deviceId = stored
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: key)
            deviceId = id
        }
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
                                accessToken: result.accessToken, displayName: result.user.name)
    }

    // MARK: - Quick Connect

    public func initiateQuickConnect(baseURL: URL) async throws -> (code: String, secret: String) {
        var req = URLRequest(url: baseURL.appendingPathComponent("QuickConnect/Initiate"))
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
                                accessToken: result.accessToken, displayName: result.user.name)
    }

    // MARK: - Token validation

    public func validateToken(credential: ServerCredential) async -> Bool {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("System/Info/Public"))
        req.setValue(authHeader(token: credential.accessToken), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Helpers

    public func authHeader(token: String? = nil) -> String {
        var parts = [
            "Client=\"Arcfin\"",
            "Device=\"\(currentDeviceName)\"",
            "DeviceId=\"\(deviceId)\"",
            "Version=\"\(Self.appVersion)\"",
        ]
        if let t = token { parts.append("Token=\"\(t)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private var currentDeviceName: String {
        #if os(iOS) || os(tvOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Arcfin"
        #endif
    }

    private func normalise(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "https://" + s }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return URL(string: s)
    }
}
