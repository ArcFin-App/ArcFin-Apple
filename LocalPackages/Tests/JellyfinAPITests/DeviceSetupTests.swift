// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network
import Testing
@testable import JellyfinAPI

@Suite("Apple TV setup")
struct DeviceSetupTests {

    @Test("A message split across reads arrives once, whole")
    func splitChunks() throws {
        var framer = DeviceSetup.Framer()
        let data = DeviceSetup.Framer.encode(.hello(profiles: [.init(userName: "Sam", serverName: "Home", servers: ["http://10.0.0.2:8096"])]))
        let middle = data.count / 2
        #expect(try framer.append(data.prefix(middle)).isEmpty)
        #expect(try framer.append(data.suffix(from: middle)) == [.hello(profiles: [.init(userName: "Sam", serverName: "Home", servers: ["http://10.0.0.2:8096"])])])
    }

    @Test("Several messages in one read")
    func severalInOne() throws {
        var framer = DeviceSetup.Framer()
        let data = DeviceSetup.Framer.encode(.allowed) + DeviceSetup.Framer.encode(.code(profile: 0, code: "123456"))
        #expect(try framer.append(data) == [.allowed, .code(profile: 0, code: "123456")])
    }

    @Test("A line that isn't a setup message is skipped")
    func garbage() throws {
        var framer = DeviceSetup.Framer()
        #expect(try framer.append(Data("hello there\n".utf8) + DeviceSetup.Framer.encode(.done(signedIn: 2))) == [.done(signedIn: 2)])
    }

    @Test("An endless line is refused")
    func oversized() {
        var framer = DeviceSetup.Framer()
        #expect(throws: (any Error).self) {
            try framer.append(Data(repeating: 0x41, count: DeviceSetup.maxMessageSize + 1))
        }
    }

    @Test("A full exchange over a local connection")
    func loopback() async throws {
        let listener = try DeviceSetupListener(advertised: false)
        defer { listener.stop() }
        let port = try await readyPort(of: listener)

        let phone = DeviceSetupChannel(endpoint: .hostPort(host: "127.0.0.1", port: port))
        defer { phone.close() }
        var incoming = listener.channels.makeAsyncIterator()
        let tv = try #require(await incoming.next())
        defer { tv.close() }

        phone.send(.hello(profiles: [.init(userName: "Sam", serverName: "Home", servers: ["http://10.0.0.2:8096"])]))
        var tvMessages = tv.messages.makeAsyncIterator()
        #expect(await tvMessages.next() == .hello(profiles: [.init(userName: "Sam", serverName: "Home", servers: ["http://10.0.0.2:8096"])]))

        tv.send(.allowed)
        tv.send(.code(profile: 0, code: "123456"))
        var phoneMessages = phone.messages.makeAsyncIterator()
        #expect(await phoneMessages.next() == .allowed)
        #expect(await phoneMessages.next() == .code(profile: 0, code: "123456"))

        phone.send(.approved(profile: 0))
        #expect(await tvMessages.next() == .approved(profile: 0))
        tv.send(.done(signedIn: 1))
        #expect(await phoneMessages.next() == .done(signedIn: 1))
    }

    @Test("The other side going away ends the messages")
    func dropped() async throws {
        let listener = try DeviceSetupListener(advertised: false)
        defer { listener.stop() }
        let port = try await readyPort(of: listener)
        let phone = DeviceSetupChannel(endpoint: .hostPort(host: "127.0.0.1", port: port))
        var incoming = listener.channels.makeAsyncIterator()
        let tv = try #require(await incoming.next())
        defer { tv.close() }
        phone.send(.hello(profiles: []))
        var tvMessages = tv.messages.makeAsyncIterator()
        _ = await tvMessages.next()
        phone.close()
        #expect(await tvMessages.next() == nil)
    }

    @Test("A last message still arrives when the sender closes after it")
    func finishDelivers() async throws {
        let listener = try DeviceSetupListener(advertised: false)
        defer { listener.stop() }
        let port = try await readyPort(of: listener)
        let phone = DeviceSetupChannel(endpoint: .hostPort(host: "127.0.0.1", port: port))
        defer { phone.close() }
        var incoming = listener.channels.makeAsyncIterator()
        let tv = try #require(await incoming.next())
        tv.finish(with: .done(signedIn: 2))
        var phoneMessages = phone.messages.makeAsyncIterator()
        #expect(await phoneMessages.next() == .done(signedIn: 2))
        #expect(await phoneMessages.next() == nil)
    }

    /// The listener reports port 0 until it's actually listening.
    private func readyPort(of listener: DeviceSetupListener) async throws -> NWEndpoint.Port {
        for _ in 0..<100 {
            if let port = listener.port, port.rawValue != 0 { return port }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CancellationError()
    }
}
