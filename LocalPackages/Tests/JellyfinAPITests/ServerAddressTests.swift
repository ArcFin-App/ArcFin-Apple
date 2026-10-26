// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Server address")
struct ServerAddressTests {

    private func response(_ url: String) -> URLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    @Test("A redirect to https is the address that's saved")
    func followsRedirectToHTTPS() {
        let base = JellyfinAuthClient.base(
            answering: response("https://jf.example.com/System/Info/Public"),
            requested: URL(string: "http://jf.example.com")!)
        #expect(base.absoluteString == "https://jf.example.com")
    }

    @Test("A path added by the redirect is kept")
    func keepsRedirectPath() {
        let base = JellyfinAuthClient.base(
            answering: response("https://example.com/jellyfin/System/Info/Public"),
            requested: URL(string: "http://example.com/jellyfin")!)
        #expect(base.absoluteString == "https://example.com/jellyfin")
    }

    @Test("No redirect keeps the typed address, port included")
    func noRedirect() {
        let typed = URL(string: "http://192.168.1.5:8096")!
        let base = JellyfinAuthClient.base(
            answering: response("http://192.168.1.5:8096/System/Info/Public"), requested: typed)
        #expect(base == typed)
    }

    @Test("A response from somewhere else keeps the typed address")
    func unrelatedResponse() {
        let typed = URL(string: "https://jf.example.com")!
        let base = JellyfinAuthClient.base(answering: response("https://login.example.com/"), requested: typed)
        #expect(base == typed)
    }
}
