// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// The iPhone as a remote (#457): the other devices this profile can control, through
/// Jellyfin, so it works away from home too. Arcfin on Apple TV, Mac or iPad answers these
/// since #455; any other Jellyfin client that can be controlled shows up as well.
@MainActor @Observable
final class RemoteSessions {
    /// Controllable sessions on other devices.
    private(set) var sessions: [JellyfinSession] = []
    /// The device the remote screen controls.
    var selectedID: String?
    var isShowingRemote = false
    /// Position counted on between polls, so the scrubber moves smoothly.
    private(set) var estimatedTicks: Int64 = 0
    /// Counts the times the list came back from the server, so the Live Activity can tell an
    /// empty list from one that was only cleared when the app went to the background.
    private(set) var refreshCount = 0

    @ObservationIgnored private weak var authManager: AuthManager?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let client = JellyfinMediaClient()

    /// The ones playing something.
    var playing: [JellyfinSession] { sessions.filter { $0.nowPlayingItemId != nil } }

    var selected: JellyfinSession? {
        playing.first { $0.id == selectedID } ?? playing.first
    }

    /// Looks every ten seconds while the app is in front, and every second while the remote
    /// screen is open.
    func start(authManager: AuthManager) {
        attach(authManager)
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.isShowingRemote ? 1 : 10))
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let session = self.selected, !session.isPaused else { continue }
                self.estimatedTicks = min(self.estimatedTicks + 5_000_000, session.runTimeTicks ?? .max)
            }
        }
    }

    /// Without polling: for a Live Activity button pressed while the app is in the background.
    func attach(_ authManager: AuthManager) {
        self.authManager = authManager
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        tickTask?.cancel()
        tickTask = nil
        sessions = []
        isShowingRemote = false
    }

    func refresh() async {
        guard let authManager, let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let ownDevice = UserDefaults.standard.string(forKey: "arcfin.deviceId")
        guard let found = try? await client.controllableSessions(credential: credential, authHeader: header) else { return }
        sessions = found.filter { $0.supportsRemoteControl && $0.deviceId != ownDevice }
        if let ticks = selected?.positionTicks { estimatedTicks = ticks }
        if isShowingRemote, selected == nil { isShowingRemote = false }
        refreshCount += 1
    }

    func open(_ session: JellyfinSession? = nil) {
        if let session { selectedID = session.id }
        estimatedTicks = selected?.positionTicks ?? 0
        isShowingRemote = true
        Task { await refresh() }
    }

    // MARK: - Commands

    private func send(_ work: @escaping (JellyfinMediaClient, String, ServerCredential, String) async -> Void) {
        guard let authManager, let credential = authManager.state.credential, let id = selected?.id else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        Task {
            await work(client, id, credential, header)
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }

    func playPause() { send { await $0.sendPlaystate(.playPause, sessionId: $1, credential: $2, authHeader: $3) } }
    func stopPlayback() { send { await $0.sendPlaystate(.stop, sessionId: $1, credential: $2, authHeader: $3) } }
    func next() { send { await $0.sendPlaystate(.nextTrack, sessionId: $1, credential: $2, authHeader: $3) } }
    func previous() { send { await $0.sendPlaystate(.previousTrack, sessionId: $1, credential: $2, authHeader: $3) } }

    func seek(to ticks: Int64) {
        let target = max(0, min(ticks, selected?.runTimeTicks ?? ticks))
        estimatedTicks = target
        send { await $0.sendPlaystate(.seek, seekTicks: target, sessionId: $1, credential: $2, authHeader: $3) }
    }

    func skip(seconds: Int) {
        seek(to: estimatedTicks + Int64(seconds) * 10_000_000)
    }

    func setVolume(_ percent: Int) {
        send { await $0.sendGeneralCommand("SetVolume", arguments: ["Volume": String(percent)], sessionId: $1, credential: $2, authHeader: $3) }
    }

    /// A press of the phone's own volume buttons.
    func stepVolume(up: Bool) {
        send { await $0.sendGeneralCommand(up ? "VolumeUp" : "VolumeDown", sessionId: $1, credential: $2, authHeader: $3) }
    }

    func toggleMute() {
        send { await $0.sendGeneralCommand("ToggleMute", sessionId: $1, credential: $2, authHeader: $3) }
    }

    func selectAudio(_ index: Int) {
        send { await $0.sendGeneralCommand("SetAudioStreamIndex", arguments: ["Index": String(index)], sessionId: $1, credential: $2, authHeader: $3) }
    }

    /// nil turns subtitles off.
    func selectSubtitle(_ index: Int?) {
        send { await $0.sendGeneralCommand("SetSubtitleStreamIndex", arguments: ["Index": String(index ?? -1)], sessionId: $1, credential: $2, authHeader: $3) }
    }

    /// "Play On": the title, from where it was left, on that device, then its remote.
    func play(_ item: MediaItem, on session: JellyfinSession) {
        guard let authManager, let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let start = item.userData.flatMap { $0.played ? nil : $0.playbackPositionTicks }
        Task {
            try? await client.play(itemIds: [item.id], startTicks: start, sessionId: session.id,
                                   credential: credential, authHeader: header)
            try? await Task.sleep(for: .seconds(2))
            open(session)
        }
    }

    /// Artwork for what a session plays, straight from the server by item id.
    func artworkURL(for session: JellyfinSession, type: String = "Backdrop", width: Int = 800) -> URL? {
        guard let id = session.nowPlayingItemId, let credential = authManager?.state.credential,
              var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Items/\(id)/Images/\(type)"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [.init(name: "fillWidth", value: String(width)), .init(name: "api_key", value: credential.accessToken)]
        return comps.url
    }
}

// MARK: - Play On

/// "Play On" in a title's menu: the devices this profile can control, to play it there.
struct PlayOnDeviceMenu: View {
    let item: MediaItem
    private var remote: RemoteSessions { AppServices.remoteSessions }

    var body: some View {
        if PlatformMetrics.controlsOtherDevices, item.type == .movie || item.type == .episode, !remote.sessions.isEmpty {
            Menu {
                ForEach(remote.sessions) { session in
                    Button(session.deviceName) { remote.play(item, on: session) }
                }
            } label: {
                Label("Play On", systemImage: "av.remote")
            }
        }
    }
}
