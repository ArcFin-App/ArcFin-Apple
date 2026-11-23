// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Listening together over SharePlay (#515): what one device sends when its person acts, and
/// what another does with it. Kept free of the player and GroupActivities so it can be tested.
///
/// Only actions are sent (play, pause, seek, skip, a new queue, an edited queue), never what a
/// player does by itself, so each device moves on to the next song on its own and nobody's
/// crossfade cuts off the end of a song for the others.
public enum ListenTogether {
    /// At most this many songs go out after the playing one: Shuffle All can queue thousands.
    public static let upcomingLimit = 50
    /// Closer than this, two positions count as the same and nobody seeks.
    public static let positionTolerance: Double = 2
    /// A message older than this when it arrives isn't trusted to say how long it travelled.
    static let latencyLimit: Double = 3

    /// The group's music at the moment someone acted.
    public struct State: Codable, Equatable, Sendable {
        /// The playing song, then up to `upcomingLimit` after it.
        public var songIDs: [String]
        public var position: Double
        public var isPlaying: Bool
        /// Nil from a device on a version that didn't send it.
        public var repeatMode: MusicQueue.RepeatMode?
        /// Higher wins; between equals, the higher sender.
        public var version: Int
        public var sender: UUID
        public var sentAt: Date

        public init(songIDs: [String], position: Double, isPlaying: Bool, repeatMode: MusicQueue.RepeatMode? = nil,
                    version: Int, sender: UUID, sentAt: Date = Date()) {
            self.songIDs = songIDs
            self.position = position
            self.isPlaying = isPlaying
            self.repeatMode = repeatMode
            self.version = version
            self.sender = sender
            self.sentAt = sentAt
        }

        public var currentID: String? { songIDs.first }
        public var upcomingIDs: ArraySlice<String> { songIDs.dropFirst() }

        /// Comes after `other` in the order everyone agrees on.
        public func supersedes(_ other: State) -> Bool {
            version != other.version ? version > other.version : sender.uuidString > other.sender.uuidString
        }
    }

    public enum Message: Codable, Equatable, Sendable {
        case state(State)
        /// A device that just joined, asking the others where they are.
        case hello
    }

    /// What this device is playing.
    public struct Local: Equatable, Sendable {
        public var currentID: String?
        public var upcomingIDs: [String]
        public var position: Double
        public var isPlaying: Bool
        public var repeatMode: MusicQueue.RepeatMode

        public init(currentID: String?, upcomingIDs: [String], position: Double, isPlaying: Bool,
                    repeatMode: MusicQueue.RepeatMode = .off) {
            self.currentID = currentID
            self.upcomingIDs = upcomingIDs
            self.position = position
            self.isPlaying = isPlaying
            self.repeatMode = repeatMode
        }
    }

    public enum Step: Equatable, Sendable {
        /// A different queue: these songs, from the first, at a position.
        case load([String], at: Double)
        /// The song is further on in this device's queue already.
        case jump(to: String)
        /// The same song, with different songs after it.
        case replaceUpcoming([String])
        case seek(to: Double)
        case setRepeat(MusicQueue.RepeatMode)
        case play
        case pause
    }

    /// The state to send for an action here, after `last`, the newest state seen so far.
    public static func state(for local: Local, after last: State?, sender: UUID, now: Date = Date()) -> State? {
        guard let current = local.currentID else { return nil }
        return State(songIDs: [current] + local.upcomingIDs.prefix(upcomingLimit), position: local.position,
                     isPlaying: local.isPlaying, repeatMode: local.repeatMode, version: (last?.version ?? 0) + 1,
                     sender: sender, sentAt: now)
    }

    /// What to do with `incoming`, given the newest state seen so far; empty when it's stale.
    public static func plan(_ incoming: State, newest: State?, local: Local, now: Date = Date()) -> [Step] {
        if let newest, incoming != newest, !incoming.supersedes(newest) { return [] }
        guard let current = incoming.currentID else { return [] }
        let position = expectedPosition(of: incoming, now: now)
        // Each device moves on by itself, so Repeat has to match for the next song to.
        let repeatSteps: [Step] = incoming.repeatMode.flatMap { $0 != local.repeatMode ? [.setRepeat($0)] : nil } ?? []
        var steps: [Step] = repeatSteps
        let upcoming = Array(incoming.upcomingIDs)
        if local.currentID != current {
            if local.upcomingIDs.contains(current) {
                steps.append(.jump(to: current))
                let after = Array(local.upcomingIDs.drop { $0 != current }.dropFirst())
                if differs(after, from: upcoming) { steps.append(.replaceUpcoming(upcoming)) }
                if position > positionTolerance { steps.append(.seek(to: position)) }
            } else {
                return [.load(incoming.songIDs, at: position)] + repeatSteps + (incoming.isPlaying ? [] : [.pause])
            }
        } else {
            if differs(local.upcomingIDs, from: upcoming) { steps.append(.replaceUpcoming(upcoming)) }
            if abs(local.position - position) > positionTolerance { steps.append(.seek(to: position)) }
        }
        let playsAfterJump = steps.contains { if case .jump = $0 { true } else { false } }
        if incoming.isPlaying, !local.isPlaying || playsAfterJump { steps.append(.play) }
        if !incoming.isPlaying, local.isPlaying || playsAfterJump { steps.append(.pause) }
        return steps
    }

    /// A list under the limit is the sender's whole queue, so anything else differs; a full
    /// one was cut short, so only its start has to match.
    static func differs(_ local: [String], from sent: [String]) -> Bool {
        sent.count < upcomingLimit ? local != sent : Array(local.prefix(sent.count)) != sent
    }

    /// Where the sender's song has got to by now: on by the time the message took, when it
    /// was playing and that time is believable.
    static func expectedPosition(of state: State, now: Date) -> Double {
        guard state.isPlaying else { return state.position }
        let travelled = now.timeIntervalSince(state.sentAt)
        return state.position + ((0...latencyLimit).contains(travelled) ? travelled : 0)
    }
}
