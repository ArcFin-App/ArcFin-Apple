// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
import JellyfinAPI
@testable import Arcfin

@MainActor
struct SeasonEpisodePicksTests {
    private func episode(_ number: Int, watched: Bool = false, virtual: Bool = false) -> MediaItem {
        MediaItem(id: "e\(number)", name: "Episode \(number)", type: .episode,
                  userData: UserData(played: watched), indexNumber: number, isVirtual: virtual)
    }

    private var season: [MediaItem] {
        [episode(1, watched: true), episode(2, watched: true), episode(3), episode(4), episode(5), episode(6), episode(7, virtual: true)]
    }

    @Test func listsOnlyEpisodesOnTheServer() {
        #expect(SeasonEpisodePicks.listed(season).map(\.id) == ["e1", "e2", "e3", "e4", "e5", "e6"])
    }

    @Test func ticksEverythingNotYetDownloaded() {
        let picks = SeasonEpisodePicks.defaults(season, taken: ["e3"], unwatchedOnly: false)
        #expect(picks == ["e1", "e2", "e4", "e5", "e6"])
    }

    @Test func ticksOnlyUnwatchedWhenSkippingWatched() {
        let picks = SeasonEpisodePicks.defaults(season, taken: ["e4"], unwatchedOnly: true)
        #expect(picks == ["e3", "e5", "e6"])
    }

    @Test func nextUnwatchedSkipsWatchedAndTaken() {
        #expect(SeasonEpisodePicks.nextUnwatched(season, taken: ["e3"]) == ["e4", "e5", "e6"])
        #expect(SeasonEpisodePicks.nextUnwatched(season, taken: ["e3", "e4", "e5"]) == ["e6"])
    }

    @Test func queuesInSeasonOrderLeavingOutTaken() {
        let ordered = SeasonEpisodePicks.ordered(season, picked: ["e6", "e1", "e4", "e3", "e7"], taken: ["e4"])
        #expect(ordered.map(\.id) == ["e1", "e3", "e6"])
    }
}
