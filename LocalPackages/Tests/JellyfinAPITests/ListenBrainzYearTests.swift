// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("ListenBrainz year")
struct ListenBrainzYearTests {
    @Test("Top songs, artists, albums and months come from ListenBrainz's stats, and a missing part is empty")
    func decodes() throws {
        let songs = #"{"payload":{"recordings":[{"track_name":"Song","artist_name":"Band","listen_count":42}]}}"#
        let artists = #"{"payload":{"artists":[{"artist_name":"Band","listen_count":90}]}}"#
        let activity = #"{"payload":{"listening_activity":[{"from_ts":1704067200,"to_ts":1706745599,"time_range":"January","listen_count":10},{"from_ts":1706745600,"to_ts":1709251199,"time_range":"February","listen_count":30}]}}"#
        let year = try ListenBrainzClient.year(songs: Data(songs.utf8), artists: Data(artists.utf8), albums: nil,
                                               activity: Data(activity.utf8))
        #expect(year.songs == [.init(name: "Song", artist: "Band", listens: 42)])
        #expect(year.artists == [.init(name: "Band", artist: nil, listens: 90)])
        #expect(year.albums.isEmpty)
        #expect(year.totalListens == 40)
        #expect(year.busiestMonth?.listens == 30)
    }
}
