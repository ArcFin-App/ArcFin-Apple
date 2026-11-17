// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore
import JellyfinAPI
import os
import Telemetry

/// Sends what plays here to the profile's ListenBrainz account, when it has a token. Listens
/// wait on disk until ListenBrainz takes them, so ones heard offline go later.
@MainActor
final class MusicScrobbler {
    private let authManager: AuthManager
    private var play: ListenBrainzPlay?
    private var listen: ListenBrainzListen?
    private var flushTask: Task<Void, Never>?
    /// ListenBrainz's id for each song played this session, which loving or hating it needs.
    private var recordingIDs: [String: String] = [:]
    /// The account's name, which reading its loves and hates needs.
    private var userNames: [UUID: String] = [:]
    private let log = Telemetry.logger(category: "ListenBrainz")
    /// Enough for weeks offline; the oldest go first past it.
    private static let maxPending = 5000

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    private var profile: UUID? { authManager.state.credential?.id }

    private static var clientVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private static func client(for profile: UUID) -> ListenBrainzClient? {
        guard !isRefused(profile), let token = ListenBrainzCredential.load(profile: profile) else { return nil }
        return ListenBrainzClient(token: token, clientVersion: clientVersion)
    }

    // MARK: Playing

    func started(_ song: MusicSong, at seconds: Double) {
        guard let profile, let client = Self.client(for: profile), let artist = song.artistLine else {
            reset()
            return
        }
        if var play, play.continues(songID: song.id, at: seconds) {
            play.moved(to: seconds)
            self.play = play
            return
        }
        let play = ListenBrainzPlay(songID: song.id, duration: song.duration, at: seconds)
        let listen = ListenBrainzListen(listenedAt: Int(play.startedAt.timeIntervalSince1970), artist: artist,
                                        track: song.name, release: song.albumName,
                                        durationMS: song.duration.map { Int($0 * 1000) })
        self.play = play
        self.listen = listen
        Task {
            guard let id = try? await client.playingNow(listen) else { return }
            recordingIDs[song.id] = id
            await loadFeedback(for: song, recordingID: id, client: client, profile: profile)
            // A song liked or disliked before, here or on the server, is passed on as it plays.
            sendFeedback(for: song.id, likes: MusicRatings.shared.likes(song.id, server: song.likes),
                         client: client, profile: profile)
        }
    }

    /// A song liked (loved there), disliked (hated) or neither. Without ListenBrainz's id for
    /// it yet, it goes the next time the song plays.
    func rated(_ songID: String, likes: Bool?) {
        guard let profile, let client = Self.client(for: profile) else { return }
        sendFeedback(for: songID, likes: likes, client: client, profile: profile)
    }

    private func sendFeedback(for songID: String, likes: Bool?, client: ListenBrainzClient, profile: UUID) {
        let score = likes.map { $0 ? 1 : -1 } ?? 0
        var sent = Self.sentFeedback(profile)
        guard let id = recordingIDs[songID], (sent[songID] ?? 0) != score else { return }
        Task {
            guard (try? await client.feedback(recordingMSID: id, score: score)) != nil else { return }
            sent = Self.sentFeedback(profile)
            sent[songID] = score == 0 ? nil : score
            UserDefaults.standard.set(sent, forKey: Self.feedbackKey(profile))
        }
    }

    /// Loved or hated on ListenBrainz and not rated here: shown here and saved to Jellyfin.
    private func loadFeedback(for song: MusicSong, recordingID: String, client: ListenBrainzClient, profile: UUID) async {
        if userNames[profile] == nil { userNames[profile] = try? await client.validate() }
        guard let name = userNames[profile],
              let score = try? await client.feedbackScore(userName: name, recordingMSID: recordingID) else { return }
        log.notice("ListenBrainz has \(score, privacy: .public) for \(song.id, privacy: .public)")
        var sent = Self.sentFeedback(profile)
        sent[song.id] = score == 0 ? nil : score
        UserDefaults.standard.set(sent, forKey: Self.feedbackKey(profile))
        guard score != 0, MusicRatings.shared.likes(song.id, server: song.likes) == nil else { return }
        MusicRatings.shared.adopt(song.id, likes: score > 0)
    }

    private static func feedbackKey(_ profile: UUID) -> String { "listenBrainzFeedback.\(profile.uuidString)" }

    private static func sentFeedback(_ profile: UUID) -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: feedbackKey(profile)) as? [String: Int] ?? [:]
    }

    /// Where the song has got to, from the progress reports and its stop.
    func heard(_ song: MusicSong, upTo seconds: Double) {
        guard var play, play.songID == song.id, let listen, let profile else { return }
        let counts = play.reached(seconds)
        self.play = play
        guard counts else { return }
        Self.savePending((Self.pending(profile) + [listen]).suffix(Self.maxPending), profile: profile)
        flush()
    }

    /// The profile changed: what was playing was the last one's.
    func reset() {
        play = nil
        listen = nil
        recordingIDs = [:]
    }

    // MARK: Sending

    func flush() {
        guard flushTask == nil, let profile, let client = Self.client(for: profile) else { return }
        flushTask = Task { [weak self] in
            while true {
                let batch = Array(Self.pending(profile).prefix(ListenBrainzClient.maxListensPerRequest))
                guard !batch.isEmpty else { break }
                do {
                    try await client.submit(batch)
                } catch ListenBrainzError.invalidToken {
                    Self.setRefused(true, profile: profile)
                    break
                } catch {
                    break
                }
                // More may have been added while these were sending; they're behind them.
                Self.savePending(Self.pending(profile).dropFirst(batch.count), profile: profile)
            }
            self?.flushTask = nil
        }
    }

    // MARK: Storage

    private static func pendingURL(_ profile: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ListenBrainz", isDirectory: true)
            .appendingPathComponent("\(profile.uuidString).json")
    }

    static func pending(_ profile: UUID) -> [ListenBrainzListen] {
        guard let data = try? Data(contentsOf: pendingURL(profile)) else { return [] }
        return (try? JSONDecoder().decode([ListenBrainzListen].self, from: data)) ?? []
    }

    private static func savePending<S: Sequence>(_ listens: S, profile: UUID) where S.Element == ListenBrainzListen {
        let url = pendingURL(profile), listens = Array(listens)
        guard !listens.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(listens).write(to: url, options: .atomic)
    }

    private static func refusedKey(_ profile: UUID) -> String { "listenBrainzRefused.\(profile.uuidString)" }

    /// ListenBrainz turned the token down; nothing is sent until a new one is saved.
    static func isRefused(_ profile: UUID) -> Bool { UserDefaults.standard.bool(forKey: refusedKey(profile)) }

    static func setRefused(_ refused: Bool, profile: UUID) {
        UserDefaults.standard.set(refused, forKey: refusedKey(profile))
    }

    /// A removed profile's token and unsent listens.
    static func forget(profile: UUID) {
        try? ListenBrainzCredential.save("", profile: profile)
        try? FileManager.default.removeItem(at: pendingURL(profile))
        UserDefaults.standard.removeObject(forKey: refusedKey(profile))
        UserDefaults.standard.removeObject(forKey: feedbackKey(profile))
    }
}
