// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Upcoming episodes")
struct UpcomingEpisodesTests {
    private func episode(_ season: Int, _ number: Int, played: Bool = false, on day: Int? = nil) -> MediaItem {
        MediaItem(id: "S\(season)E\(number)", name: "", type: .episode,
                  userData: UserData(played: played, lastPlayedDate: day.map { Date(timeIntervalSince1970: Double($0) * 86_400) }),
                  indexNumber: number, parentIndexNumber: season)
    }

    @Test("Later seasons marked watched long ago don't hide the episode after the latest watch")
    func followsLatestWatch() {
        let all = [episode(0, 1), episode(1, 1, played: true, on: 100), episode(1, 2, played: true, on: 101),
                   episode(1, 3), episode(1, 4), episode(2, 1, played: true, on: 10), episode(2, 2, played: true, on: 11)]
        #expect(JellyfinMediaClient.upcoming(in: all, count: 2).map(\.id) == ["S1E3", "S1E4"])
    }

    @Test("Specials are never picked, so nothing restarts from season 0")
    func skipsSpecials() {
        let all = [episode(0, 1), episode(0, 2), episode(1, 1), episode(1, 2)]
        #expect(JellyfinMediaClient.upcoming(in: all, count: 1).map(\.id) == ["S1E1"])
    }

    @Test("Without dates, after the last episode marked watched")
    func withoutDates() {
        let all = [episode(1, 1, played: true), episode(1, 2), episode(1, 3, played: true), episode(1, 4)]
        #expect(JellyfinMediaClient.upcoming(in: all, count: 3).map(\.id) == ["S1E4"])
    }
}
