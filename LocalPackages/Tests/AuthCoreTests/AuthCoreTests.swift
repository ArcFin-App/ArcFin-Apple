// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import AuthCore

@Suite("ServerCredential")
struct AuthCoreTests {

    @Test("ServerCredential is equatable by id")
    func credentialEquality() throws {
        let url = try #require(URL(string: "https://jellyfin.example.com"))
        let cred = ServerCredential(baseURL: url, userID: "u1", accessToken: "tok", displayName: "Home")
        #expect(cred == cred)
    }

    @Test("AuthState unauthenticated by default")
    func defaultAuthState() {
        let state = AuthState.unauthenticated
        #expect(state == .unauthenticated)
    }
}

@Suite("CustomHTTPHeaders per server")
struct CustomHTTPHeadersTests {
    private let header = CustomHTTPHeaders.Header(name: "CF-Access-Client-Id", value: "id")
    private func noAddresses(_: UUID) -> [String] { [] }

    @Test("Default ports match by host, other ports by host and port")
    func origins() throws {
        #expect(CustomHTTPHeaders.origin(of: try #require(URL(string: "https://JF.example.com/Items"))) == "jf.example.com")
        #expect(CustomHTTPHeaders.origin(of: try #require(URL(string: "http://jf.example.com:80"))) == "jf.example.com")
        #expect(CustomHTTPHeaders.origin(of: try #require(URL(string: "http://10.0.0.5:8096/web"))) == "10.0.0.5:8096")
        #expect(CustomHTTPHeaders.origin(ofAddress: "jf.example.com") == "jf.example.com")
        #expect(CustomHTTPHeaders.origin(ofAddress: "  ") == nil)
    }

    @Test("Headers saved while signing in go to that server only")
    func signInAddress() throws {
        var stored = CustomHTTPHeaders.Stored()
        CustomHTTPHeaders.update(&stored, headers: [header], scope: .address("jf.example.com"), addresses: noAddresses)
        let own = try #require(URL(string: "https://jf.example.com/Items/1/Images/Primary"))
        let tmdb = try #require(URL(string: "https://image.tmdb.org/t/p/w500/x.jpg"))
        let seerr = try #require(URL(string: "http://jf.example.com:5055/api/v1"))
        #expect(CustomHTTPHeaders.server(for: own, in: stored, addresses: noAddresses)?.headers == [header])
        #expect(CustomHTTPHeaders.server(for: tmdb, in: stored, addresses: noAddresses) == nil)
        #expect(CustomHTTPHeaders.server(for: seerr, in: stored, addresses: noAddresses) == nil)
    }

    @Test("A profile's Local and Remote URLs count as its server's addresses")
    func profileAddresses() throws {
        let credential = ServerCredential(baseURL: try #require(URL(string: "https://jf.example.com")),
                                          userID: "u", accessToken: "t", displayName: "Home")
        var stored = CustomHTTPHeaders.Stored()
        CustomHTTPHeaders.update(&stored, headers: [header], scope: .server(credential), addresses: noAddresses)
        let addresses: (UUID) -> [String] = { $0 == credential.id ? ["http://192.168.1.5:8096"] : [] }
        let local = try #require(URL(string: "http://192.168.1.5:8096/System/Ping"))
        #expect(CustomHTTPHeaders.server(for: local, in: stored, addresses: addresses) != nil)
        #expect(CustomHTTPHeaders.server(for: local, in: stored, addresses: noAddresses) == nil)
    }

    @Test("Another server keeps its own headers, and clearing them removes only that server's")
    func twoServers() throws {
        let home = ServerCredential(baseURL: try #require(URL(string: "https://home.example.com")),
                                    userID: "a", accessToken: "t", displayName: "Home")
        let friend = ServerCredential(baseURL: try #require(URL(string: "https://friend.example.net")),
                                      userID: "b", accessToken: "t", displayName: "Friend")
        let other = CustomHTTPHeaders.Header(name: "X-Token", value: "secret")
        var stored = CustomHTTPHeaders.Stored()
        CustomHTTPHeaders.update(&stored, headers: [header], scope: .server(home), addresses: noAddresses)
        CustomHTTPHeaders.update(&stored, headers: [other], scope: .server(friend), addresses: noAddresses)
        #expect(CustomHTTPHeaders.server(for: friend.baseURL, in: stored, addresses: noAddresses)?.headers == [other])
        CustomHTTPHeaders.update(&stored, headers: [], scope: .server(friend), addresses: noAddresses)
        #expect(CustomHTTPHeaders.server(for: friend.baseURL, in: stored, addresses: noAddresses) == nil)
        #expect(CustomHTTPHeaders.server(for: home.baseURL, in: stored, addresses: noAddresses)?.headers == [header])
    }

    @Test("Headers with no server yet aren't sent, and move to the address they're saved for")
    func unassigned() throws {
        var stored = CustomHTTPHeaders.Stored(unassigned: [header])
        #expect(stored.servers.isEmpty)
        CustomHTTPHeaders.update(&stored, headers: [header], scope: .address("jf.example.com"), addresses: noAddresses)
        #expect(stored.unassigned.isEmpty)
        #expect(CustomHTTPHeaders.server(for: try #require(URL(string: "wss://jf.example.com/socket")),
                                         in: stored, addresses: noAddresses) != nil)
    }
}

@Suite("CustomHTTPHeaders upgrade")
struct CustomHTTPHeadersMigrationTests {
    private let header = CustomHTTPHeaders.Header(name: "X-Token", value: "secret")

    private func profile(_ address: String) throws -> ServerCredential {
        ServerCredential(baseURL: try #require(URL(string: address)), userID: "u", accessToken: "t", displayName: "P")
    }

    @Test("Saved headers move to the profile in use")
    func activeProfile() throws {
        let first = try profile("https://one.example.com"), active = try profile("https://two.example.com")
        let stored = try CustomHTTPHeaders.migrated([header], profiles: [first, active], activeID: active.id)
        #expect(stored.servers.map(\.profileIDs) == [[active.id]])
        #expect(stored.servers.first?.origins == ["two.example.com"])
    }

    @Test("Without a profile marked in use, the first profile gets them")
    func firstProfile() throws {
        let first = try profile("https://one.example.com"), second = try profile("https://two.example.com")
        let stored = try CustomHTTPHeaders.migrated([header], profiles: [first, second], activeID: nil)
        #expect(stored.servers.map(\.profileIDs) == [[first.id]])
    }

    @Test("With no profiles they wait unassigned, unless profiles just couldn't be read")
    func noProfiles() throws {
        let stored = try CustomHTTPHeaders.migrated([header], profiles: [], activeID: nil)
        #expect(stored.servers.isEmpty && stored.unassigned == [header])
        #expect(throws: (any Error).self) { try CustomHTTPHeaders.migrated([header], profiles: [], activeID: UUID()) }
    }
}
