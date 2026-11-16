// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The devices playing on this profile and the commands that control them, as the iPhone
/// remote does (#457). Looks every two seconds while the app is in front.
@MainActor @Observable
final class WatchRemote {
    private(set) var sessions: [WatchSession] = []
    private(set) var hasLoaded = false
    private(set) var cannotReachServer = false
    /// Counted on between polls, so the bar moves smoothly.
    private(set) var estimatedTicks: [String: Int64] = [:]

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    private var client: WatchJellyfin? { WatchSignIn.shared.credential.map(WatchJellyfin.init) }

    func session(_ id: String) -> WatchSession? { sessions.first { $0.id == id } }

    func position(of session: WatchSession) -> Int64 { estimatedTicks[session.id] ?? session.positionTicks }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                for session in sessions where !session.isPaused {
                    let ticks = position(of: session) + 5_000_000
                    estimatedTicks[session.id] = min(ticks, session.runTimeTicks)
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        tickTask?.cancel()
        tickTask = nil
    }

    func refresh() async {
        guard let client else {
            sessions = []
            return
        }
        do {
            sessions = try await client.playingSessions()
            estimatedTicks = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.positionTicks) })
            cannotReachServer = false
        } catch {
            cannotReachServer = true
        }
        hasLoaded = true
    }

    func artworkURL(for session: WatchSession) -> URL? { client?.artworkURL(itemID: session.itemID) }

    // MARK: - Commands

    private func send(_ work: @escaping @MainActor (WatchJellyfin) async -> Void) {
        guard let client else { return }
        Task {
            await work(client)
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }

    func playPause(_ session: WatchSession) { send { await $0.playstate("PlayPause", sessionID: session.id) } }
    func stopPlayback(_ session: WatchSession) { send { await $0.playstate("Stop", sessionID: session.id) } }
    func next(_ session: WatchSession) { send { await $0.playstate("NextTrack", sessionID: session.id) } }
    func previous(_ session: WatchSession) { send { await $0.playstate("PreviousTrack", sessionID: session.id) } }

    func skip(_ session: WatchSession, seconds: Int) {
        let target = max(0, min(position(of: session) + Int64(seconds) * 10_000_000, session.runTimeTicks))
        estimatedTicks[session.id] = target
        send { await $0.playstate("Seek", seekTicks: target, sessionID: session.id) }
    }

    func setVolume(_ session: WatchSession, to percent: Int) {
        send { await $0.command("SetVolume", arguments: ["Volume": String(percent)], sessionID: session.id) }
    }

    func toggleMute(_ session: WatchSession) { send { await $0.command("ToggleMute", sessionID: session.id) } }

    func selectAudio(_ session: WatchSession, index: Int) {
        send { await $0.command("SetAudioStreamIndex", arguments: ["Index": String(index)], sessionID: session.id) }
    }

    /// nil turns subtitles off.
    func selectSubtitle(_ session: WatchSession, index: Int?) {
        send { await $0.command("SetSubtitleStreamIndex", arguments: ["Index": String(index ?? -1)], sessionID: session.id) }
    }
}
