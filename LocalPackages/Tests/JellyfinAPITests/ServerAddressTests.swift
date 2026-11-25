// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Server address")
struct ServerAddressTests {

    private func response(_ url: String) -> URLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    @Test("A typed address is tried as given, slips put right", arguments: [
        ("http://10.0.0.5:8096", ["http://10.0.0.5:8096"]),
        ("HTTPS://jf.example.com/", ["https://jf.example.com"]),
        ("http:/10.0.0.5:8096", ["http://10.0.0.5:8096"]),
        ("http//10.0.0.5:8096", ["http://10.0.0.5:8096"]),
        ("https:///example.com/jellyfin//", ["https://example.com/jellyfin"]),
        ("10.0.0.5:8096", ["https://10.0.0.5:8096", "http://10.0.0.5:8096"]),
        ("jf.example.com", ["https://jf.example.com", "http://jf.example.com"]),
        ("[fe80::1]:8096", ["https://[fe80::1]:8096", "http://[fe80::1]:8096"]),
        ("httpbin.example.com", ["https://httpbin.example.com", "http://httpbin.example.com"]),
    ])
    func candidates(typed: String, expected: [String]) throws {
        #expect(try JellyfinAuthClient.candidates(for: typed).map(\.absoluteString) == expected)
    }

    @Test("Another scheme is refused before anything is sent")
    func wrongScheme() {
        #expect(throws: JellyfinAuthError.unsupportedScheme("htt")) {
            try JellyfinAuthClient.candidates(for: "htt://10.0.0.5:8096")
        }
        #expect(throws: JellyfinAuthError.unsupportedScheme("ftp")) {
            try JellyfinAuthClient.candidates(for: "ftp://jf.example.com")
        }
    }

    @Test("Something that isn't an address is refused", arguments: ["", "   ", "my server", "http://", "https:///"])
    func notAnAddress(typed: String) {
        #expect(throws: JellyfinAuthError.invalidServerURL) {
            try JellyfinAuthClient.candidates(for: typed)
        }
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

    @Test("A web page instead of Jellyfin's API reads as not Jellyfin")
    func htmlIsNotJellyfin() {
        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "HTML"))
        #expect(JellyfinAuthClient.reason(for: error) == .notJellyfin)
    }

    @Test("Network failures map to their reasons", arguments: [
        (URLError.Code.serverCertificateUntrusted, JellyfinAuthError.certificateProblem),
        (.cannotFindHost, .hostNotFound),
        (.cannotConnectToHost, .connectionRefused),
        (.timedOut, .timedOut),
        (.notConnectedToInternet, .offline),
        (.badServerResponse, .serverUnreachable),
    ])
    func networkReasons(code: URLError.Code, reason: JellyfinAuthError) {
        #expect(JellyfinAuthClient.reason(for: URLError(code)) == reason)
    }
}
