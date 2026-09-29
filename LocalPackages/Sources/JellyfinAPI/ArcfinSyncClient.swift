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

public enum ArcfinSyncError: Error, Sendable {
    case requestFailed
}

// MARK: - Client

/// Talks to the companion "Arcfin Sync" Jellyfin server plugin (git.psmattas.com/ArcFin/Arcfin-Sync),
/// not part of Jellyfin core. `fetchStatus` is deliberately non-throwing — a server that doesn't
/// have the plugin installed, or isn't reachable, should look identical to "not installed" rather
/// than surfacing an error to the caller (see AuthManager.refreshArcfinSync).
public struct ArcfinSyncClient: Sendable {
    public init() {}

    public func fetchStatus(baseURL: URL) async -> ArcfinSyncStatus? {
        var req = URLRequest(url: baseURL.appendingPathComponent("ArcfinSync/Status"))
        req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(ArcfinSyncStatus.self, from: data)
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
