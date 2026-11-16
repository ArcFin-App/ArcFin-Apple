// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation
import Network
import Testing
@testable import JellyfinAPI

@Suite("Apple TV setup")
struct DeviceSetupTests {

    private let profile = DeviceSetup.Profile(userName: "Sam", serverName: "Home",
                                              servers: ["http://10.0.0.2:8096"], tmdbKey: "abc123")

    // MARK: - Framing

    @Test("A message split across reads arrives once, whole")
    func splitChunks() throws {
        var framer = DeviceSetup.Framer()
        let data = DeviceSetup.Framer.encode(.commit(Data(repeating: 7, count: 32)))
        let middle = data.count / 2
        #expect(try framer.append(data.prefix(middle)).isEmpty)
        #expect(try framer.append(data.suffix(from: middle)) == [.commit(Data(repeating: 7, count: 32))])
    }

    @Test("A line that isn't a setup message is skipped")
    func garbage() throws {
        var framer = DeviceSetup.Framer()
        #expect(try framer.append(Data("hello there\n".utf8) + DeviceSetup.Framer.encode(.key(Data([1])))) == [.key(Data([1]))])
    }

    @Test("An endless line is refused")
    func oversized() {
        var framer = DeviceSetup.Framer()
        #expect(throws: (any Error).self) {
            try framer.append(Data(repeating: 0x41, count: DeviceSetup.maxMessageSize + 1))
        }
    }

    // MARK: - Keys and sealing

    private func keys(phone: Curve25519.KeyAgreement.PrivateKey, tv: Curve25519.KeyAgreement.PrivateKey) throws -> DeviceSetup.Keys {
        let secret = try phone.sharedSecretFromKeyAgreement(with: tv.publicKey)
        return DeviceSetup.Keys(secret: secret, phoneKey: phone.publicKey.rawRepresentation, tvKey: tv.publicKey.rawRepresentation)
    }

    @Test("Someone in the middle ends up with a different code")
    func middleChangesCode() throws {
        let phone = Curve25519.KeyAgreement.PrivateKey()
        let tv = Curve25519.KeyAgreement.PrivateKey()
        let middle = Curve25519.KeyAgreement.PrivateKey()
        let real = try keys(phone: phone, tv: tv)
        // The phone talks to the middle, which talks to the TV: each pair agrees different keys.
        let phoneSide = try keys(phone: phone, tv: middle)
        let tvSide = try keys(phone: middle, tv: tv)
        #expect(real.code.count == 6)
        #expect(phoneSide.code != tvSide.code)
    }

    @Test("A changed, replayed or reordered message doesn't open")
    func sealing() throws {
        let k = try keys(phone: .init(), tv: .init())
        var phone = DeviceSetup.Cipher(send: k.phoneToTV, receive: k.tvToPhone)
        var tv = DeviceSetup.Cipher(send: k.tvToPhone, receive: k.phoneToTV)

        let first = try phone.seal(.hello(profiles: [profile]))
        let second = try phone.seal(.approved(profile: 0))
        var changed = first
        changed[changed.startIndex] ^= 0x01
        #expect(throws: (any Error).self) { try tv.open(changed) }
        #expect(try tv.open(first) == .hello(profiles: [profile]))
        #expect(throws: (any Error).self) { try tv.open(first) }

        var fresh = DeviceSetup.Cipher(send: k.tvToPhone, receive: k.phoneToTV)
        #expect(throws: (any Error).self) { try fresh.open(second) }
    }

    @Test("A message sealed one way doesn't open the other")
    func directions() throws {
        let k = try keys(phone: .init(), tv: .init())
        var phone = DeviceSetup.Cipher(send: k.phoneToTV, receive: k.tvToPhone)
        let sealed = try phone.seal(.allowed(signedIn: []))
        #expect(throws: (any Error).self) { try phone.open(sealed) }
    }

    // MARK: - Over a connection

    @Test("A full exchange: same code on both sides, then sealed messages")
    func loopback() async throws {
        let listener = try DeviceSetupListener(advertised: false)
        defer { listener.stop() }
        let port = try await readyPort(of: listener)

        let phone = try await DeviceSetupSession.connect(to: .hostPort(host: "127.0.0.1", port: port))
        defer { phone.close() }
        var incoming = listener.sessions.makeAsyncIterator()
        let tv = try #require(await incoming.next())
        defer { tv.close() }
        #expect(phone.code == tv.code)
        #expect(phone.code.count == 6)

        phone.send(.hello(profiles: [profile]))
        var tvMessages = tv.messages.makeAsyncIterator()
        #expect(await tvMessages.next() == .hello(profiles: [profile]))

        tv.send(.allowed(signedIn: ["u1"]))
        tv.send(.code(profile: 0, code: "123456"))
        var phoneMessages = phone.messages.makeAsyncIterator()
        #expect(await phoneMessages.next() == .allowed(signedIn: ["u1"]))
        #expect(await phoneMessages.next() == .code(profile: 0, code: "123456"))

        phone.send(.approved(profile: 0))
        #expect(await tvMessages.next() == .approved(profile: 0))
        tv.finish(with: .done(signedIn: 1))
        #expect(await phoneMessages.next() == .done(signedIn: 1))
        #expect(await phoneMessages.next() == nil)
    }

    @Test("An Apple TV whose key doesn't match its commitment is refused")
    func brokenCommitment() async throws {
        // A fake Apple TV that commits to one key and reveals another.
        let fake = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "fake-tv")
        fake.newConnectionHandler = { connection in
            let channel = DeviceSetupChannel(connection: connection)
            channel.send(.commit(DeviceSetup.commitment(key: Data(repeating: 1, count: 32), nonce: Data(repeating: 2, count: 32))))
            Task {
                for await wire in channel.messages {
                    guard case .key = wire else { continue }
                    channel.send(.reveal(key: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
                                         nonce: Data(repeating: 2, count: 32)))
                }
            }
        }
        fake.start(queue: queue)
        defer { fake.cancel() }
        var port: NWEndpoint.Port?
        for _ in 0..<100 {
            if let p = fake.port, p.rawValue != 0 { port = p; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let ready = try #require(port)
        await #expect(throws: DeviceSetupSession.HandshakeError.self) {
            _ = try await DeviceSetupSession.connect(to: .hostPort(host: "127.0.0.1", port: ready))
        }
    }

    @Test("The Apple TV takes one exchange at a time")
    func oneAtATime() async throws {
        let listener = try DeviceSetupListener(advertised: false)
        defer { listener.stop() }
        let port = try await readyPort(of: listener)
        // A connection that never finishes the exchange holds the Apple TV.
        let stuck = DeviceSetupChannel(connection: NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: .tcp))
        defer { stuck.close() }
        var stuckMessages = stuck.messages.makeAsyncIterator()
        guard case .commit? = await stuckMessages.next() else {
            Issue.record("The TV didn't commit first")
            return
        }
        // A second one meanwhile is turned away.
        let second = DeviceSetupChannel(connection: NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: .tcp))
        defer { second.close() }
        var secondMessages = second.messages.makeAsyncIterator()
        #expect(await secondMessages.next() == nil)
    }

    @Test("The other side going away ends the messages")
    func dropped() async throws {
        let listener = try DeviceSetupListener(advertised: false)
        defer { listener.stop() }
        let port = try await readyPort(of: listener)
        let phone = try await DeviceSetupSession.connect(to: .hostPort(host: "127.0.0.1", port: port))
        var incoming = listener.sessions.makeAsyncIterator()
        let tv = try #require(await incoming.next())
        defer { tv.close() }
        phone.close()
        var tvMessages = tv.messages.makeAsyncIterator()
        #expect(await tvMessages.next() == nil)
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
