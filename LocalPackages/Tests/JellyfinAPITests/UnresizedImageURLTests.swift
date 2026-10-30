// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Unresized image URL")
struct UnresizedImageURLTests {

    @Test("Drops the resize parameters and keeps the tag and token")
    func dropsResizeParameters() throws {
        let url = JellyfinMediaClient.imageURL(
            baseURL: URL(string: "https://jf.example.com")!, itemID: "abc", tag: "t1",
            type: .primary, fillWidth: 300, token: "key")
        let original = try #require(JellyfinMediaClient.unresizedImageURL(url))
        let items = URLComponents(url: original, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(Set(items.map(\.name)) == ["tag", "api_key"])
        #expect(original.path == "/Items/abc/Images/Primary")
    }

    @Test("Drops max sizes too")
    func dropsMaxSizes() throws {
        let url = URL(string: "https://jf.example.com/Items/abc/Images/Logo/0?maxWidth=400&maxHeight=200&tag=t1")!
        let original = try #require(JellyfinMediaClient.unresizedImageURL(url))
        #expect(original.query == "tag=t1")
    }

    @Test("A URL that asks for no resize has nothing to fall back to")
    func noResize() {
        let url = URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg")!
        #expect(JellyfinMediaClient.unresizedImageURL(url) == nil)
    }
}
