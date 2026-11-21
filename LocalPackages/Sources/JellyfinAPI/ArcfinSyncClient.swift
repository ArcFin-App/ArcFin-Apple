// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Response models

public struct ArcfinSyncStatus: Sendable, Decodable, Equatable {
    public let installed: Bool
    public let version: String

    enum CodingKeys: String, CodingKey {
        case installed = "Installed"
        case version = "Version"
    }
}

public struct ArcfinSyncedSetting: Sendable, Codable, Equatable {
    public let key: String
    public let value: String?
    public let isLocked: Bool

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case value = "Value"
        case isLocked = "IsLocked"
    }
}

/// What the plugin's test encodes found: whether h264, hevc and av1 can be encoded with the
/// server's hardware acceleration setting.
public struct ArcfinSyncEncoders: Sendable, Decodable, Equatable {
    public let hardwareAcceleration: String
    public let encoders: [String: Bool]
    /// When the server last ran its test encodes.
    public let probedAt: Date?

    enum CodingKeys: String, CodingKey {
        case hardwareAcceleration = "HardwareAcceleration"
        case encoders = "Encoders"
        case probedAt = "ProbedAt"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hardwareAcceleration = try container.decode(String.self, forKey: .hardwareAcceleration)
        encoders = try container.decode([String: Bool].self, forKey: .encoders)
        probedAt = (try? container.decode(String.self, forKey: .probedAt)).flatMap(JellyfinDate.parse)
    }
}

/// What the server says about the plugin.
public enum ArcfinSyncPresence: Sendable, Equatable {
    case installed(ArcfinSyncStatus)
    /// The server answered without it: a 404, as after it's removed, or a status saying so.
    case notInstalled
    /// No answer, or one that says nothing either way (a proxy's 502 while Jellyfin is down).
    case unknown
}

public enum ArcfinSyncError: Error, Sendable {
    case requestFailed
}

// MARK: - Client

/// Talks to the companion "Arcfin Sync" Jellyfin server plugin (git.psmattas.com/ArcFin/Arcfin-Sync),
/// not part of Jellyfin core. `fetchStatus` is deliberately non-throwing: a server without the
/// plugin, or one that can't be reached, isn't an error to show (see AuthManager.refreshArcfinSync).
public struct ArcfinSyncClient: Sendable {
    public init() {}

    public func fetchStatus(baseURL: URL) async -> ArcfinSyncPresence {
        var req = URLRequest(url: baseURL.appendingPathComponent("ArcfinSync/Status"))
        req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
              let status = (resp as? HTTPURLResponse)?.statusCode
        else { return .unknown }
        if status == 404 { return .notInstalled }
        guard status == 200, let decoded = try? JSONDecoder().decode(ArcfinSyncStatus.self, from: data)
        else { return .unknown }
        return decoded.installed ? .installed(decoded) : .notInstalled
    }

    /// Nil on a plugin from before the encoder check, or when it can't be reached.
    /// `refresh` makes the server run its test encodes again.
    public func fetchEncoders(credential: ServerCredential, authHeader: String, refresh: Bool = false) async -> ArcfinSyncEncoders? {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("ArcfinSync/Encoders"), resolvingAgainstBaseURL: false)!
        if refresh { comps.queryItems = [.init(name: "refresh", value: "true")] }
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        // The first call runs the server's test encodes, a few seconds each.
        req.timeoutInterval = 90
        guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(ArcfinSyncEncoders.self, from: data)
    }

    /// One audio track of an item, copied out by Arcfin Sync with the server's ffmpeg as AAC
    /// in an .m4a. A plugin from before this answers 404.
    public static func audioTrackURL(baseURL: URL, itemID: String, mediaSourceId: String, audioStreamIndex: Int, token: String) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("ArcfinSync/Items/\(itemID)/Audio/\(audioStreamIndex)"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "mediaSourceId", value: mediaSourceId), .init(name: "api_key", value: token)]
        return comps.url!
    }

    public func fetchSettings(credential: ServerCredential, authHeader: String) async throws -> [ArcfinSyncedSetting] {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("ArcfinSync/Settings"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ArcfinSyncError.requestFailed }
        return try JSONDecoder().decode([ArcfinSyncedSetting].self, from: data)
    }

    public func updateSettings(
        credential: ServerCredential,
        authHeader: String,
        values: [String: String]
    ) async throws -> [ArcfinSyncedSetting] {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("ArcfinSync/Settings"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        req.httpBody = try JSONEncoder().encode(values)
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ArcfinSyncError.requestFailed }
        return try JSONDecoder().decode([ArcfinSyncedSetting].self, from: data)
    }
}
