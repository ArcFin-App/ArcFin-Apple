// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import MediaEngine

struct ListenTogetherTests {
    typealias State = ListenTogether.State
    typealias Local = ListenTogether.Local

    let me = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let them = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let now = Date(timeIntervalSince1970: 1_000_000)

    func state(_ ids: [String], at position: Double = 0, playing: Bool = true, version: Int = 1,
               sender: UUID? = nil, sentAt: Date? = nil) -> State {
        State(songIDs: ids, position: position, isPlaying: playing, version: version, sender: sender ?? them,
              sentAt: sentAt ?? now)
    }

    @Test func sendsTheSongAndAtMostFiftyAfterIt() throws {
        let local = Local(currentID: "a", upcomingIDs: (0..<200).map { "s\($0)" }, position: 12, isPlaying: true)
        let sent = try #require(ListenTogether.state(for: local, after: state(["x"], version: 4), sender: me, now: now))
        #expect(sent.songIDs.count == 1 + ListenTogether.upcomingLimit)
        #expect(sent.currentID == "a")
        #expect(sent.version == 5)
        #expect(sent.position == 12)
    }

    @Test func nothingToSendWithoutASong() {
        #expect(ListenTogether.state(for: Local(currentID: nil, upcomingIDs: [], position: 0, isPlaying: false),
                                     after: nil, sender: me) == nil)
    }

    @Test func aDifferentQueueLoadsAndKeepsItsPause() {
        let local = Local(currentID: "x", upcomingIDs: ["y"], position: 30, isPlaying: true)
        let steps = ListenTogether.plan(state(["a", "b"], at: 40, playing: false), newest: nil, local: local, now: now)
        #expect(steps == [.load(["a", "b"], at: 40), .pause])
    }

    @Test func aSongFurtherOnIsJumpedTo() {
        let local = Local(currentID: "a", upcomingIDs: ["b", "c"], position: 200, isPlaying: true)
        let steps = ListenTogether.plan(state(["b", "c"]), newest: nil, local: local, now: now)
        #expect(steps == [.jump(to: "b"), .play])
    }

    @Test func anEditedQueueReplacesWhatComesNext() {
        let local = Local(currentID: "a", upcomingIDs: ["b", "c"], position: 10, isPlaying: true)
        let steps = ListenTogether.plan(state(["a", "c", "b"], at: 10), newest: nil, local: local, now: now)
        #expect(steps == [.replaceUpcoming(["c", "b"])])
    }

    @Test func aClearedQueueClearsHereToo() {
        let local = Local(currentID: "a", upcomingIDs: ["b", "c"], position: 10, isPlaying: true)
        #expect(ListenTogether.plan(state(["a"], at: 10), newest: nil, local: local, now: now) == [.replaceUpcoming([])])
    }

    @Test func aCutShortQueueOnlyHasToMatchItsStart() {
        let long = (0..<300).map { "s\($0)" }
        let local = Local(currentID: "a", upcomingIDs: long, position: 10, isPlaying: true)
        let sent = state(["a"] + long.prefix(ListenTogether.upcomingLimit), at: 10)
        #expect(ListenTogether.plan(sent, newest: nil, local: local, now: now).isEmpty)
    }

    @Test func aSeekMovesOnlyBeyondTheTolerance() {
        let local = Local(currentID: "a", upcomingIDs: [], position: 60, isPlaying: true)
        #expect(ListenTogether.plan(state(["a"], at: 61), newest: nil, local: local, now: now).isEmpty)
        #expect(ListenTogether.plan(state(["a"], at: 90), newest: nil, local: local, now: now) == [.seek(to: 90)])
    }

    @Test func aPlayingPositionCountsTheTimeItTookToArrive() {
        let local = Local(currentID: "a", upcomingIDs: [], position: 0, isPlaying: true)
        let sent = state(["a"], at: 100, sentAt: now.addingTimeInterval(-2))
        #expect(ListenTogether.plan(sent, newest: nil, local: local, now: now) == [.seek(to: 102)])
        // A clock that's far out isn't believed.
        let skewed = state(["a"], at: 100, sentAt: now.addingTimeInterval(-60))
        #expect(ListenTogether.plan(skewed, newest: nil, local: local, now: now) == [.seek(to: 100)])
    }

    @Test func pauseAndPlayFollowTheSender() {
        let playing = Local(currentID: "a", upcomingIDs: [], position: 50, isPlaying: true)
        #expect(ListenTogether.plan(state(["a"], at: 50, playing: false), newest: nil, local: playing, now: now) == [.pause])
        let paused = Local(currentID: "a", upcomingIDs: [], position: 50, isPlaying: false)
        #expect(ListenTogether.plan(state(["a"], at: 50), newest: nil, local: paused, now: now) == [.play])
    }

    @Test func anOlderStateIsIgnored() {
        let local = Local(currentID: "a", upcomingIDs: [], position: 0, isPlaying: true)
        let newest = state(["a"], version: 5)
        #expect(ListenTogether.plan(state(["z"], version: 4), newest: newest, local: local, now: now).isEmpty)
    }

    @Test func aTieGoesToTheHigherSender() {
        let mine = state(["a"], version: 3, sender: me)
        let theirs = state(["b"], version: 3, sender: them)
        #expect(theirs.supersedes(mine))
        #expect(!mine.supersedes(theirs))
        let local = Local(currentID: "a", upcomingIDs: [], position: 0, isPlaying: true)
        #expect(ListenTogether.plan(theirs, newest: mine, local: local, now: now) == [.load(["b"], at: 0)])
        #expect(ListenTogether.plan(mine, newest: theirs, local: local, now: now).isEmpty)
    }

    @Test func messagesRoundTrip() throws {
        let message = ListenTogether.Message.state(state(["a", "b"], at: 3.5, playing: false, version: 9))
        let decoded = try JSONDecoder().decode(ListenTogether.Message.self, from: JSONEncoder().encode(message))
        #expect(decoded == message)
        let hello = try JSONDecoder().decode(ListenTogether.Message.self, from: JSONEncoder().encode(ListenTogether.Message.hello))
        #expect(hello == .hello)
    }
}
