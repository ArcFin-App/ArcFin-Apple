import Foundation
import AuthCore

// MARK: - SyncPlay models

public struct SyncPlayGroupInfo: Sendable, Identifiable, Equatable {
    public let id: String
    public let groupName: String
    public let participants: [String]
    public let playingItemName: String?
}

/// A playback command broadcast to every member of a SyncPlay group (including the sender)
/// once the server processes a Play/Pause/Seek REST call. Clients apply the command only
/// once it arrives back over the WebSocket, rather than optimistically applying it locally
/// first — that's what keeps every group member's timeline the same command, not a mix of
/// "my own local action" plus "everyone else's echoed action".
public struct SyncPlayCommand: Sendable, Equatable {
    public enum Kind: String, Sendable { case play = "Play", pause = "Pause", seek = "Seek", stop = "Stop" }
    public let kind: Kind
    public let positionTicks: Int64?
}

extension JellyfinMediaClient {

    // MARK: - Group management

    public func syncPlayCreateGroup(credential: ServerCredential, authHeader: String, groupName: String) async throws {
        try await syncPlayPost(credential: credential, authHeader: authHeader, path: "SyncPlay/New", body: ["GroupName": groupName])
    }

    public func syncPlayListGroups(credential: ServerCredential, authHeader: String) async throws -> [SyncPlayGroupInfo] {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("SyncPlay/List"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([SyncPlayGroupResponse].self, from: data).map {
            SyncPlayGroupInfo(id: $0.groupId, groupName: $0.groupName, participants: $0.participants ?? [], playingItemName: $0.playingItemName)
        }
    }

    public func syncPlayJoinGroup(credential: ServerCredential, authHeader: String, groupId: String) async throws {
        try await syncPlayPost(credential: credential, authHeader: authHeader, path: "SyncPlay/Join", body: ["GroupId": groupId])
    }

    public func syncPlayLeaveGroup(credential: ServerCredential, authHeader: String) async throws {
        try await syncPlayPost(credential: credential, authHeader: authHeader, path: "SyncPlay/Leave", body: nil)
    }

    /// Tells the group what's queued so the server accepts subsequent Play/Pause/Seek for
    /// it — called right after creating/joining a group with the item already open locally.
    /// MVP scope: every participant must have the same item open in their own player
    /// already (no cross-client "everyone jump to this title" — see SyncPlayManager's note).
    public func syncPlaySetQueue(credential: ServerCredential, authHeader: String, itemId: String, startPositionTicks: Int64) async throws {
        try await syncPlayPost(credential: credential, authHeader: authHeader, path: "SyncPlay/SetNewQueue", body: [
            "PlayingQueue": [itemId], "PlayingItemPosition": 0, "StartPositionTicks": startPositionTicks,
        ])
    }

    // MARK: - Playback commands (broadcast to the whole group, echoed back to the sender too)

    public func syncPlayRequestPlay(credential: ServerCredential, authHeader: String) async throws {
        try await syncPlayPost(credential: credential, authHeader: authHeader, path: "SyncPlay/Play", body: nil)
    }

    public func syncPlayRequestPause(credential: ServerCredential, authHeader: String) async throws {
        try await syncPlayPost(credential: credential, authHeader: authHeader, path: "SyncPlay/Pause", body: nil)
    }

    public func syncPlayRequestSeek(credential: ServerCredential, authHeader: String, positionTicks: Int64) async throws {
        try await syncPlayPost(credential: credential, authHeader: authHeader, path: "SyncPlay/Seek", body: ["PositionTicks": positionTicks])
    }

    private func syncPlayPost(credential: ServerCredential, authHeader: String, path: String, body: [String: Any]?) async throws {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (_, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

private struct SyncPlayGroupResponse: Decodable {
    let groupId: String
    let groupName: String
    let participants: [String]?
    let playingItemName: String?
    enum CodingKeys: String, CodingKey {
        case groupId = "GroupId"
        case groupName = "GroupName"
        case participants = "Participants"
        case playingItemName = "PlayingItemName"
    }
}
