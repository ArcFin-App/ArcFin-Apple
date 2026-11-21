// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation
import GroupActivities
import JellyfinAPI
import MediaEngine
import Observation
import SwiftUI

/// Listening to music together over FaceTime (#515). Everyone streams from their own account
/// on the same Jellyfin server, so the activity carries the server's id.
nonisolated struct ListenTogetherActivity: GroupActivity {
    let serverId: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .listenTogether
        metadata.title = String(localized: "Music in Arcfin")
        metadata.supportsContinuationOnTV = true
        return metadata
    }
}

/// The music side of SharePlay: what someone here does to the music goes to the group, and
/// what someone there does is played here. `ListenTogether` decides both; this moves the
/// messages and the player. Each device moves on to the next song by itself.
@MainActor @Observable
final class MusicSharePlay {
    static let shared = MusicSharePlay()

    private(set) var isActive = false
    private(set) var participantCount = 0

    @ObservationIgnored var currentServerId: () -> String = { "" }
    @ObservationIgnored private var session: GroupSession<ListenTogetherActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// The newest state seen, sent or received; anything older is ignored.
    @ObservationIgnored private var newest: ListenTogether.State?
    @ObservationIgnored private let me = UUID()
    /// Steps from the group being played here, so they aren't sent back to it.
    @ObservationIgnored private var applying = 0
    @ObservationIgnored private var pendingSend: Task<Void, Never>?
    @ObservationIgnored private var pendingPlaying: Bool?
    /// This device started the session, so its music is what the group hears first.
    @ObservationIgnored private var startedHere = false
    @ObservationIgnored private var isObserving = false
    /// Joined from the call while the app lock was up; it starts once the lock opens.
    @ObservationIgnored private var heldSession: GroupSession<ListenTogetherActivity>?

    private var music: MusicPlayback { AppServices.music }

    /// Runs for the life of the app: sessions arrive here whether this device started them or
    /// joined from the call.
    func observeSessions() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }
        for await session in ListenTogetherActivity.sessions() {
            if AppServices.hasPassedLock { configure(session) } else { heldSession = session }
        }
    }

    func runHeld() {
        guard let session = heldSession else { return }
        heldSession = nil
        if case .invalidated = session.state { return }
        configure(session)
    }

    func start() {
        let activity = ListenTogetherActivity(serverId: currentServerId())
        Task {
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                startedHere = true
                if (try? await activity.activate()) != true { startedHere = false }
            case .activationDisabled:
                AppServices.sharePlayManager.notice = String(localized: "Start a FaceTime call first, then choose SharePlay.")
            default:
                break
            }
        }
    }

    func leave() {
        session?.leave()
        reset()
    }

    // MARK: Session

    private func configure(_ session: GroupSession<ListenTogetherActivity>) {
        let startedHere = self.startedHere
        reset()
        let serverId = currentServerId()
        guard serverId.isEmpty || session.activity.serverId == serverId else {
            AppServices.sharePlayManager.notice = String(localized: "The music is on a Jellyfin server you're not signed in to here.")
            session.leave()
            return
        }
        self.session = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger
        isActive = true
        music.isListeningTogether = true
        music.onUserAction = { [weak self] playing in self?.localAction(playing) }

        tasks.append(Task { [weak self] in
            for await state in session.$state.values {
                if case .invalidated = state { self?.reset() }
            }
        })
        tasks.append(Task { [weak self] in
            for await participants in session.$activeParticipants.values {
                self?.participantCount = participants.count
            }
        })
        tasks.append(Task { [weak self] in
            for await (message, _) in messenger.messages(of: ListenTogether.Message.self) {
                self?.received(message)
            }
        })
        session.join()
        // Whoever started it shares what they're playing; everyone else asks.
        if startedHere, music.player.current != nil {
            send(playing: nil)
        } else {
            Task { try? await messenger.send(ListenTogether.Message.hello) }
        }
    }

    private func reset() {
        tasks.forEach { $0.cancel() }
        tasks = []
        pendingSend?.cancel()
        pendingSend = nil
        pendingPlaying = nil
        session = nil
        messenger = nil
        newest = nil
        startedHere = false
        isActive = false
        participantCount = 0
        music.isListeningTogether = false
        music.onUserAction = nil
    }

    // MARK: Sending

    /// Sent a moment later, so a flick of the scrubber or a run of skips goes out once, and the
    /// player has caught up with what was asked.
    private func localAction(_ playing: Bool?) {
        guard applying == 0, isActive else { return }
        if let playing { pendingPlaying = playing }
        pendingSend?.cancel()
        pendingSend = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            send(playing: pendingPlaying)
            pendingPlaying = nil
        }
    }

    private func send(playing: Bool?) {
        var local = local()
        if let playing { local.isPlaying = playing }
        guard let messenger, let state = ListenTogether.state(for: local, after: newest, sender: me) else { return }
        newest = state
        Task { try? await messenger.send(ListenTogether.Message.state(state)) }
    }

    /// A device that just joined: what's playing here, without taking over from anyone.
    private func reply() {
        guard let messenger, let current = music.player.current else { return }
        let local = local()
        let state = ListenTogether.State(songIDs: [current.id] + local.upcomingIDs.prefix(ListenTogether.upcomingLimit),
                                         position: local.position, isPlaying: local.isPlaying,
                                         repeatMode: local.repeatMode, version: newest?.version ?? 0, sender: me)
        Task { try? await messenger.send(ListenTogether.Message.state(state)) }
    }

    private func local() -> ListenTogether.Local {
        ListenTogether.Local(currentID: music.player.current?.id,
                             upcomingIDs: music.player.queue.upNext.map(\.track.id),
                             position: music.position, isPlaying: music.isPlaying,
                             repeatMode: music.player.repeatMode)
    }

    // MARK: Receiving

    private func received(_ message: ListenTogether.Message) {
        switch message {
        case .hello:
            reply()
        case .state(let state):
            let steps = ListenTogether.plan(state, newest: newest, local: local())
            if newest.map({ state.supersedes($0) }) ?? true { newest = state }
            guard !steps.isEmpty else { return }
            Task { await apply(steps) }
        }
    }

    private func apply(_ steps: [ListenTogether.Step]) async {
        applying += 1
        defer { applying -= 1 }
        for step in steps {
            switch step {
            case .load(let ids, let seconds):
                _ = await music.playFromRemote(ids, startIndex: 0, startTicks: Int64(seconds * 10_000_000))
            case .jump(let id):
                if let entry = music.player.queue.upNext.first(where: { $0.track.id == id }) { music.jump(to: entry.id) }
            case .replaceUpcoming(let ids):
                guard let songs = await Self.songs(ids) else { continue }
                music.player.clearUpNext()
                music.player.addToQueue(songs)
            case .seek(let seconds):
                music.seek(to: seconds)
            case .setRepeat(let mode):
                music.player.repeatMode = mode
            case .play:
                music.resume()
            case .pause:
                music.pause()
            }
        }
    }

    /// The songs in the order given; nil when the server didn't answer.
    private static func songs(_ ids: [String]) async -> [MusicSong]? {
        guard !ids.isEmpty else { return [] }
        guard let found = try? await MusicAPI.call({ try await $0.getSongs(credential: $1, authHeader: $2, ids: ids) })
        else { return nil }
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
}

/// Starts listening together, or leaves; in Now Playing's menu and the Mac's bar.
struct MusicSharePlayButton: View {
    var iconOnly = false
    private var sharePlay: MusicSharePlay { .shared }

    var body: some View {
        let title: LocalizedStringKey = sharePlay.isActive ? "Leave SharePlay" : "SharePlay"
        Button {
            sharePlay.isActive ? sharePlay.leave() : sharePlay.start()
        } label: {
            if iconOnly {
                Image(systemName: "shareplay")
                    .foregroundStyle(sharePlay.isActive ? DT.Color.accent : Color.primary)
            } else if sharePlay.isActive {
                Label("Leave SharePlay", systemImage: "shareplay.slash")
            } else {
                Label("SharePlay", systemImage: "shareplay")
            }
        }
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}
