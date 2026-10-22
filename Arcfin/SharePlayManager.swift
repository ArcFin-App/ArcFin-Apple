// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import Combine
import GroupActivities
import CoreTransferable
import JellyfinAPI

/// Watching a title together over FaceTime. Everyone streams from their own account on the
/// same Jellyfin server, so the activity carries the server's id along with the title's.
nonisolated struct WatchTogetherActivity: GroupActivity {
    let itemId: String
    let serverId: String
    let title: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .watchTogether
        metadata.title = title
        metadata.supportsContinuationOnTV = true
        return metadata
    }
}

#if !os(tvOS)
/// Lets the share sheet start SharePlay outside a FaceTime call.
struct WatchTogetherItem: Transferable {
    let activity: WatchTogetherActivity

    static var transferRepresentation: some TransferRepresentation {
        GroupActivityTransferRepresentation { $0.activity }
    }
}
#endif

nonisolated struct SharePlayCommand: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case play, pause, seek
        /// Sent by a player that just opened, so the others answer with where they are.
        case hello
    }

    var kind: Kind
    var itemId: String
    var positionTicks: Int64
    var id = UUID()
}

/// Same shape as SyncPlay, except a command is applied locally as it's sent: SharePlay's
/// messenger doesn't echo a message back to its sender.
@MainActor
@Observable
final class SharePlayManager {
    private(set) var isActive = false
    private(set) var participantCount = 0
    /// The title the group is watching; a player showing something else switches to it.
    private(set) var activityItemId: String?
    /// PlayerView applies this exactly once.
    var incomingCommand: SharePlayCommand?
    var notice: String?
    /// The title open in the player here, if any.
    private(set) var playingItemId: String?
    var hasOpenPlayer: Bool { playingItemId != nil }

    @ObservationIgnored private var session: GroupSession<WatchTogetherActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored var currentServerId: () -> String = { "" }
    @ObservationIgnored private var isObserving = false

    /// Runs for the life of the app: sessions arrive here whether this device started them or
    /// joined from the call.
    func observeSessions() async {
        // Every window shares this manager; one listener is enough.
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }
        for await session in WatchTogetherActivity.sessions() {
            configure(session)
        }
    }

    func activity(for item: MediaItem) -> WatchTogetherActivity {
        WatchTogetherActivity(itemId: item.id, serverId: currentServerId(), title: Self.title(for: item))
    }

    func start(_ item: MediaItem) {
        let activity = activity(for: item)
        Task {
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                _ = try? await activity.activate()
            case .activationDisabled:
                notice = "Start a FaceTime call first, then choose SharePlay."
            default:
                break
            }
        }
    }

    func leave() {
        session?.leave()
        reset()
    }

    // MARK: - Player

    /// A player opened on `item`. When the group is watching something else, this device
    /// moves everyone to it, as picking a new title does in any SharePlay app.
    func playerOpened(_ item: MediaItem) {
        playingItemId = item.id
        guard isActive else { return }
        if activityItemId != item.id {
            session?.activity = activity(for: item)
            activityItemId = item.id
        }
        send(.hello, itemId: item.id, positionTicks: 0)
    }

    /// By id, because the next title's player can open before the last one has closed.
    func playerClosed(_ itemId: String) {
        if playingItemId == itemId { playingItemId = nil }
    }

    func send(_ kind: SharePlayCommand.Kind, itemId: String, positionTicks: Int64) {
        guard let messenger else { return }
        let command = SharePlayCommand(kind: kind, itemId: itemId, positionTicks: positionTicks)
        Task { try? await messenger.send(command) }
    }

    // MARK: - Session

    private func configure(_ session: GroupSession<WatchTogetherActivity>) {
        reset()
        // Before Home has loaded the server's id isn't known yet; the title then simply fails
        // to load if it's from another server.
        let serverId = currentServerId()
        guard serverId.isEmpty || session.activity.serverId == serverId else {
            notice = "\(session.activity.title) is on a Jellyfin server you're not signed in to here."
            session.leave()
            return
        }
        self.session = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger
        isActive = true

        tasks.append(Task { [weak self] in
            for await state in session.$state.values {
                if case .invalidated = state { self?.reset() }
            }
        })
        tasks.append(Task { [weak self] in
            for await activity in session.$activity.values {
                self?.follow(activity)
            }
        })
        tasks.append(Task { [weak self] in
            for await participants in session.$activeParticipants.values {
                self?.participantCount = participants.count
            }
        })
        tasks.append(Task { [weak self] in
            for await (command, _) in messenger.messages(of: SharePlayCommand.self) {
                self?.incomingCommand = command
            }
        })
        session.join()
    }

    private func follow(_ activity: WatchTogetherActivity) {
        guard activityItemId != activity.itemId else { return }
        activityItemId = activity.itemId
        // An open player switches by itself (it watches activityItemId); otherwise open one.
        if playingItemId == nil { WatchRoute.open(id: activity.itemId) }
    }

    private func reset() {
        tasks.forEach { $0.cancel() }
        tasks = []
        session = nil
        messenger = nil
        isActive = false
        participantCount = 0
        activityItemId = nil
    }

    private static func title(for item: MediaItem) -> String {
        guard item.type == .episode, let series = item.seriesName else { return item.name }
        return "\(series) – \(item.name)"
    }
}
