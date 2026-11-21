// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
import JellyfinAPI
@testable import MediaEngine

@Suite("MusicQueue")
struct MusicQueueTests {

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private static func tracks(_ names: String...) -> [MusicSong] {
        names.map { MusicSong(id: $0, name: $0) }
    }

    private static func ids(_ entries: some Sequence<MusicQueue.Entry>) -> [String] {
        entries.map(\.track.id)
    }

    @Test("Starts at the song asked for")
    func startsAtIndex() {
        let queue = MusicQueue(Self.tracks("a", "b", "c"), startingAt: 1)
        #expect(queue.current?.track.id == "b")
        #expect(Self.ids(queue.upNext) == ["c"])
        #expect(Self.ids(queue.history) == ["a"])
    }

    @Test("Ends after the last song with repeat off, wraps with repeat all")
    func advanceAtEnd() {
        var queue = MusicQueue(Self.tracks("a", "b"), startingAt: 1)
        #expect(queue.advance() == nil)
        #expect(queue.current?.track.id == "b")
        queue.repeatMode = .all
        #expect(queue.advance()?.track.id == "a")
    }

    @Test("Repeat one repeats a song that ends, but a skip moves on")
    func repeatOne() {
        var queue = MusicQueue(Self.tracks("a", "b"))
        queue.repeatMode = .one
        #expect(queue.advance(finished: true)?.track.id == "a")
        #expect(queue.advance()?.track.id == "b")
    }

    @Test("Back restarts a song that's been playing, else goes back one")
    func goBack() {
        var queue = MusicQueue(Self.tracks("a", "b"), startingAt: 1)
        #expect(queue.goBack(from: 10)?.track.id == "b")
        #expect(queue.goBack(from: 1)?.track.id == "a")
        #expect(queue.goBack(from: 1)?.track.id == "a")
        queue.repeatMode = .all
        #expect(queue.goBack(from: 1)?.track.id == "b")
    }

    @Test("Play next goes right after the current song; add to queue goes last")
    func playNextAndAdd() {
        var queue = MusicQueue(Self.tracks("a", "b"))
        queue.playNext(Self.tracks("x", "y"))
        queue.addToQueue(Self.tracks("z"))
        #expect(Self.ids(queue.entries) == ["a", "x", "y", "b", "z"])
    }

    @Test("Adding to an empty queue makes the first song current")
    func addToEmpty() {
        var queue = MusicQueue()
        queue.playNext(Self.tracks("a"))
        #expect(queue.current?.track.id == "a")
    }

    @Test("One song can be queued twice and removed once")
    func duplicates() {
        var queue = MusicQueue(Self.tracks("a", "b"))
        queue.addToQueue(Self.tracks("a"))
        let second = queue.entries[2].id
        queue.remove(second)
        #expect(Self.ids(queue.entries) == ["a", "b"])
        #expect(queue.currentIndex == 0)
    }

    @Test("Removing an earlier song keeps the current one current")
    func removeBefore() {
        var queue = MusicQueue(Self.tracks("a", "b", "c"), startingAt: 2)
        queue.remove(queue.entries[0].id)
        #expect(queue.current?.track.id == "c")
    }

    @Test("Removing the current song makes the next one current")
    func removeCurrent() {
        var queue = MusicQueue(Self.tracks("a", "b", "c"))
        queue.remove(queue.entries[0].id)
        #expect(queue.current?.track.id == "b")
    }

    @Test("Moving in Up Next leaves the current song alone")
    func move() {
        var queue = MusicQueue(Self.tracks("a", "b", "c", "d"))
        queue.moveUpNext(from: 2, to: 0)
        #expect(Self.ids(queue.entries) == ["a", "d", "b", "c"])
        #expect(queue.current?.track.id == "a")
    }

    @Test("Clearing Up Next keeps what's played and what's playing")
    func clear() {
        var queue = MusicQueue(Self.tracks("a", "b", "c"), startingAt: 1)
        queue.clearUpNext()
        #expect(Self.ids(queue.entries) == ["a", "b"])
        #expect(queue.advance() == nil)
    }

    @Test("Shuffle keeps the current song first and every song once")
    func shuffle() {
        var generator = Seeded(state: 7)
        var queue = MusicQueue(Self.tracks("a", "b", "c", "d", "e"), startingAt: 2)
        queue.setShuffled(true, using: &generator)
        #expect(queue.current?.track.id == "c")
        #expect(queue.currentIndex == 0)
        #expect(Set(Self.ids(queue.entries)) == ["a", "b", "c", "d", "e"])
        #expect(queue.entries.count == 5)
    }

    @Test("Shuffle off goes back to the first order, at the current song")
    func unshuffle() {
        var generator = Seeded(state: 7)
        var queue = MusicQueue(Self.tracks("a", "b", "c", "d"), shuffled: true, using: &generator)
        queue.advance()
        let playing = queue.current?.track.id
        queue.setShuffled(false)
        #expect(Self.ids(queue.entries) == ["a", "b", "c", "d"])
        #expect(queue.current?.track.id == playing)
    }

    @Test("Songs added while shuffled stay after turning shuffle off")
    func addWhileShuffled() {
        var generator = Seeded(state: 3)
        var queue = MusicQueue(Self.tracks("a", "b", "c"), shuffled: true, using: &generator)
        queue.addToQueue(Self.tracks("z"))
        queue.setShuffled(false)
        #expect(Self.ids(queue.entries) == ["a", "b", "c", "z"])
    }
}
