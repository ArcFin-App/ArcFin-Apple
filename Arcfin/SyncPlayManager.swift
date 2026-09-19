import Foundation
import Observation
import AuthCore
import JellyfinAPI

/// SyncPlay (Jellyfin's native group-watch protocol) — MVP scope: every participant opens
/// the same item in their own player first (this app doesn't yet push a remote "everyone
/// jump to this title" navigation), then one creates a group and others join it from the
/// list. From that point, play/pause/seek made by any member broadcasts to the whole group
/// and every client — including the one who triggered it — applies the command only once
/// it comes back over the WebSocket, so everyone reacts to the same authoritative event
/// instead of the sender also self-applying it locally first.
///
/// Not implemented (documented scope cuts, not oversights): the Buffering/Ready handshake
/// that pauses the group while one member's stream catches up, and a precise clock-offset
/// ping for sub-second timing — commands are applied as soon as they arrive, which is good
/// enough for a casual watch-together but can drift by however long the round trip takes.
@MainActor
@Observable
final class SyncPlayManager {
    private(set) var currentGroupId: String?
    private(set) var groupName: String?
    private(set) var availableGroups: [SyncPlayGroupInfo] = []
    private(set) var isRefreshingGroups = false
    var lastError: String?

    /// PlayerView observes this to apply an incoming command exactly once.
    var incomingCommand: SyncPlayCommand?

    var isInGroup: Bool { currentGroupId != nil }

    @ObservationIgnored private var socket: JellyfinWebSocketClient?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private let client = JellyfinMediaClient()
    @ObservationIgnored private let deviceId: String = {
        UserDefaults.standard.string(forKey: "arcfin.deviceId") ?? UUID().uuidString
    }()

    // MARK: - Groups

    func refreshGroups(credential: ServerCredential, authHeader: String) async {
        isRefreshingGroups = true
        availableGroups = (try? await client.syncPlayListGroups(credential: credential, authHeader: authHeader)) ?? []
        isRefreshingGroups = false
    }

    func createGroup(
        credential: ServerCredential, authHeader: String, groupName: String,
        itemId: String, startPositionTicks: Int64
    ) async {
        do {
            try await client.syncPlayCreateGroup(credential: credential, authHeader: authHeader, groupName: groupName)
            // The server assigns the new group as this session's current group — list to
            // find its id, matching by name (List returns no other way to identify "the one
            // I just made" from a bare success response).
            let groups = (try? await client.syncPlayListGroups(credential: credential, authHeader: authHeader)) ?? []
            guard let created = groups.first(where: { $0.groupName == groupName }) else {
                lastError = "Group was created but couldn't be found."
                return
            }
            try await client.syncPlaySetQueue(credential: credential, authHeader: authHeader, itemId: itemId, startPositionTicks: startPositionTicks)
            currentGroupId = created.id
            self.groupName = created.groupName
            connectSocket(credential: credential, authHeader: authHeader)
        } catch {
            lastError = "Couldn't create the group. Check your connection and try again."
        }
    }

    func joinGroup(
        _ group: SyncPlayGroupInfo, credential: ServerCredential, authHeader: String,
        itemId: String, startPositionTicks: Int64
    ) async {
        do {
            try await client.syncPlayJoinGroup(credential: credential, authHeader: authHeader, groupId: group.id)
            try await client.syncPlaySetQueue(credential: credential, authHeader: authHeader, itemId: itemId, startPositionTicks: startPositionTicks)
            currentGroupId = group.id
            groupName = group.groupName
            connectSocket(credential: credential, authHeader: authHeader)
        } catch {
            lastError = "Couldn't join that group — it may have just ended."
        }
    }

    func leaveGroup(credential: ServerCredential, authHeader: String) {
        Task { try? await client.syncPlayLeaveGroup(credential: credential, authHeader: authHeader) }
        disconnectSocket()
        currentGroupId = nil
        groupName = nil
    }

    // MARK: - Playback commands

    func requestPlay(credential: ServerCredential, authHeader: String) {
        Task { try? await client.syncPlayRequestPlay(credential: credential, authHeader: authHeader) }
    }

    func requestPause(credential: ServerCredential, authHeader: String) {
        Task { try? await client.syncPlayRequestPause(credential: credential, authHeader: authHeader) }
    }

    func requestSeek(credential: ServerCredential, authHeader: String, positionTicks: Int64) {
        Task { try? await client.syncPlayRequestSeek(credential: credential, authHeader: authHeader, positionTicks: positionTicks) }
    }

    // MARK: - WebSocket

    private func connectSocket(credential: ServerCredential, authHeader: String) {
        disconnectSocket()
        let socket = JellyfinWebSocketClient(credential: credential, deviceId: deviceId)
        self.socket = socket
        listenTask = Task { [weak self] in
            for await event in socket.events {
                guard let self else { return }
                switch event {
                case .syncPlayCommand(let command):
                    self.incomingCommand = command
                case .syncPlayGroupChanged:
                    // Cheap and simple: re-derive participant/group state from the REST
                    // list rather than parse every GroupUpdate variant's nested payload.
                    await self.refreshGroups(credential: credential, authHeader: authHeader)
                case .syncPlayGroupGone:
                    self.currentGroupId = nil
                    self.groupName = nil
                    self.disconnectSocket()
                }
            }
        }
    }

    private func disconnectSocket() {
        listenTask?.cancel()
        listenTask = nil
        socket?.close()
        socket = nil
    }
}
