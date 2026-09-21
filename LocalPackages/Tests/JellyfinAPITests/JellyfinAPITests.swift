// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
@testable import JellyfinAPI

@Suite("MediaItem")
struct JellyfinAPITests {

    @Test("MediaItem equality by id")
    func mediaItemEquality() {
        let item1 = MediaItem(id: "abc", name: "Test Movie", type: .movie)
        let item2 = MediaItem(id: "abc", name: "Test Movie", type: .movie)
        #expect(item1 == item2)
    }

    @Test("UserData default values")
    func userDataDefaults() {
        let data = UserData()
        #expect(data.played == false)
        #expect(data.playCount == 0)
    }
}
