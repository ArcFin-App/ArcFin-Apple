// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import AppIntents
import Foundation

// Compiled into both the app and the widget extension. They're audio playback intents, so the
// system runs them inside the app (starting it in the background if need be), where the
// handler the app sets at launch plays the music; in the extension they're only declared.

enum MusicIntentCommand: Sendable {
    case togglePlayPause
    case setPlaying(Bool)
    case next
    case previous
    /// Plays the widget's Recently Played list from this song.
    case play(songID: String)
}

@MainActor
enum MusicIntentPerformer {
    /// Throws when the app lock is up and the command would start music.
    static var handle: ((MusicIntentCommand) async throws -> Void)?
}

struct ToggleMusicPlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play or Pause Music"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await MusicIntentPerformer.handle?(.togglePlayPause)
        return .result()
    }
}

struct NextSongIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Song"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await MusicIntentPerformer.handle?(.next)
        return .result()
    }
}

struct PreviousSongIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Song"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await MusicIntentPerformer.handle?(.previous)
        return .result()
    }
}

struct PlayRecentSongIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Song"
    static let isDiscoverable = false

    @Parameter(title: "Song") var songID: String

    init() {}
    init(songID: String) { self.songID = songID }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await MusicIntentPerformer.handle?(.play(songID: songID))
        return .result()
    }
}

/// Control Center's music toggle.
struct SetMusicPlayingIntent: SetValueIntent, AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Music"
    static let isDiscoverable = false

    @Parameter(title: "Playing") var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        try await MusicIntentPerformer.handle?(.setPlaying(value))
        return .result()
    }
}
#endif
