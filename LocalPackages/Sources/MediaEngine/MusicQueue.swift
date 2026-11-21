// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI

/// What plays now and next. Each entry has its own ID, so one song can be in the queue twice.
/// Shuffle keeps the order it was started in, so turning it off goes back to that order.
public struct MusicQueue: Sendable, Equatable {
    public struct Entry: Sendable, Identifiable, Equatable, Hashable {
        public let id: UUID
        public let track: MusicSong

        public init(_ track: MusicSong, id: UUID = UUID()) {
            self.id = id
            self.track = track
        }
    }

    public enum RepeatMode: String, Sendable, CaseIterable {
        case off, all, one
    }

    /// In play order: shuffled when shuffle is on.
    public private(set) var entries: [Entry]
    public private(set) var currentIndex: Int?
    public private(set) var isShuffled = false
    public var repeatMode: RepeatMode = .off
    private var unshuffled: [Entry]

    /// Past this, previous starts the song again instead of going back one.
    public static let restartThreshold: Double = 3

    public init() {
        entries = []
        unshuffled = []
    }

    public init(_ tracks: [MusicSong], startingAt index: Int = 0, shuffled: Bool = false) {
        var generator = SystemRandomNumberGenerator()
        self.init(tracks, startingAt: index, shuffled: shuffled, using: &generator)
    }

    public init(_ tracks: [MusicSong], startingAt index: Int = 0, shuffled: Bool = false,
                using generator: inout some RandomNumberGenerator) {
        entries = tracks.map { Entry($0) }
        unshuffled = entries
        currentIndex = entries.indices.contains(index) ? index : (entries.isEmpty ? nil : 0)
        if shuffled { setShuffled(true, using: &generator) }
    }

    public var current: Entry? { currentIndex.map { entries[$0] } }
    public var upNext: ArraySlice<Entry> { currentIndex.map { entries[($0 + 1)...] } ?? entries[...] }
    public var history: ArraySlice<Entry> { currentIndex.map { entries[..<$0] } ?? [] }
    public var isEmpty: Bool { entries.isEmpty }

    /// The song after this one, if any. A song that ends by itself repeats under repeat one;
    /// a skip moves on.
    @discardableResult
    public mutating func advance(finished: Bool = false) -> Entry? {
        guard let index = currentIndex else { return nil }
        if finished, repeatMode == .one { return current }
        if index + 1 < entries.count {
            currentIndex = index + 1
        } else if repeatMode != .off {
            currentIndex = 0
        } else {
            return nil
        }
        return current
    }

    /// Back one song, or to the start of this one once it's been playing a moment.
    /// Returns the entry to play from its start.
    @discardableResult
    public mutating func goBack(from positionSeconds: Double) -> Entry? {
        guard let index = currentIndex else { return nil }
        if positionSeconds > Self.restartThreshold { return current }
        if index > 0 {
            currentIndex = index - 1
        } else if repeatMode == .all {
            currentIndex = entries.count - 1
        }
        return current
    }

    @discardableResult
    public mutating func jump(to id: Entry.ID) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        currentIndex = index
        return current
    }

    /// Right after the current song, in the order given.
    public mutating func playNext(_ tracks: [MusicSong]) {
        let added = tracks.map { Entry($0) }
        guard let index = currentIndex else { return append(added) }
        entries.insert(contentsOf: added, at: index + 1)
        let at = unshuffled.firstIndex(of: entries[index]).map { $0 + 1 } ?? unshuffled.endIndex
        unshuffled.insert(contentsOf: added, at: at)
    }

    public mutating func addToQueue(_ tracks: [MusicSong]) {
        append(tracks.map { Entry($0) })
    }

    private mutating func append(_ added: [Entry]) {
        entries.append(contentsOf: added)
        unshuffled.append(contentsOf: added)
        if currentIndex == nil, !entries.isEmpty { currentIndex = 0 }
    }

    /// Removing the current song makes the next one current; the caller plays it.
    public mutating func remove(_ id: Entry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        unshuffled.removeAll { $0.id == id }
        guard let current = currentIndex else { return }
        if entries.isEmpty {
            currentIndex = nil
        } else if index < current {
            currentIndex = current - 1
        } else if index == current {
            currentIndex = min(current, entries.count - 1)
        }
    }

    /// Moves within Up Next only; what's played and what's playing stay put.
    public mutating func moveUpNext(from source: Int, to destination: Int) {
        let base = (currentIndex ?? -1) + 1
        let from = base + source
        guard entries.indices.contains(from) else { return }
        let entry = entries.remove(at: from)
        let to = min(max(base + destination, base), entries.count)
        entries.insert(entry, at: to)
        if !isShuffled { unshuffled = entries }
    }

    /// Keeps only the current song.
    public mutating func clearUpNext() {
        guard let index = currentIndex else { return }
        entries = Array(entries[...index])
        let kept = Set(entries.map(\.id))
        unshuffled.removeAll { !kept.contains($0.id) }
    }

    public mutating func setShuffled(_ on: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffled(on, using: &generator)
    }

    /// On: the current song stays and everything else is shuffled after it. Off: the order it
    /// was started in, at the current song.
    public mutating func setShuffled(_ on: Bool, using generator: inout some RandomNumberGenerator) {
        guard on != isShuffled else { return }
        isShuffled = on
        let current = current
        if on {
            var rest = entries.filter { $0 != current }
            rest.shuffle(using: &generator)
            entries = (current.map { [$0] } ?? []) + rest
            currentIndex = entries.isEmpty ? nil : 0
        } else {
            entries = unshuffled
            currentIndex = current.flatMap { entries.firstIndex(of: $0) } ?? (entries.isEmpty ? nil : 0)
        }
    }
}
