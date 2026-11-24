// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

/// Keys, a rotation and a command made by the Arcfin Sync plugin's own signer, so the two sides
/// can't drift apart.
@Suite struct ServerCommandVerifierTests {
    static let first = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEwATG4A01zJzZWlq80Vxmmqfh8FAP16Wqdv6DUsgp5BqkLqaam1ozmLKeatJKncZNiZ/oTC7uXauFlGs2qzMI3g=="
    static let second = ServerSigningKey(
        publicKey: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEXpSwqqCCIWWTa56Cw7GQgiy0VWsOpMUBhwfaUApNJ8uhbsAehVJZYO9HMPY6ouRaq8Yc+GKL57Ph2nOCxfODWA==",
        fingerprint: "65:5F:DD:57:59:14:AD:72",
        previousPublicKey: first,
        rotationSignature: "ESBhNpi+6pN+e6XwW9SZ8G8HMt1mFE5miUeGrF95zcT+akX3FqGPWbMz2D+MNic1tUMKbb9e8lthoh3Viu8ynA==")
    static let lock = SignedServerCommand(
        payload: "eyJ2IjoxLCJraW5kIjoibG9jayIsInVzZXIiOiIwZjhmYWQ1YmQ5Y2I0NjlmYTE2NTcwODY3NzI4OTUwZSIsInNlcnZlciI6InNlcnZlcmlkIiwiY291bnRlciI6MSwiaXNzdWVkIjoxODkzNDU2MDAwLCJleHBpcmVzIjoyMjA4ODE2MDAwfQ==",
        signature: "uqJDmxlINbmYB2DSoQ8XeHCpUtZg7FeY63Lnr3VyRwO3HhssZwA9HPfP8yY8TDvzZ9C723UiiV+i/fjGNi/u4Q==")
    static let user = "0f8fad5b-d9cb-469f-a165-70867728950e"
    static let now = Date(timeIntervalSince1970: 1_893_456_100)

    @Test func firstKeyIsPinned() {
        #expect(ServerCommandVerifier.decide(Self.second, pinned: nil) == .pin(Self.second.publicKey))
    }

    @Test func signedRotationMovesThePin() {
        #expect(ServerCommandVerifier.decide(Self.second, pinned: Self.first) == .pin(Self.second.publicKey))
        #expect(ServerCommandVerifier.decide(Self.second, pinned: Self.second.publicKey) == .same)
    }

    @Test func unsignedKeyChangeIsRefused() {
        let forged = ServerSigningKey(publicKey: Self.second.publicKey, fingerprint: "", previousPublicKey: Self.first, rotationSignature: Self.lock.signature)
        #expect(ServerCommandVerifier.decide(forged, pinned: Self.first) == .changed)
        let other = ServerSigningKey(publicKey: Self.first, fingerprint: "", previousPublicKey: nil, rotationSignature: nil)
        #expect(ServerCommandVerifier.decide(other, pinned: Self.second.publicKey) == .changed)
    }

    @Test func pluginCommandVerifies() throws {
        let command = try #require(ServerCommandVerifier.verify(Self.lock, publicKey: Self.second.publicKey, userID: Self.user.replacingOccurrences(of: "-", with: ""), now: Self.now))
        #expect(command.commandKind == .lock)
        #expect(command.counter == 1)
    }

    @Test func wrongKeyUserOrTimeFails() {
        #expect(ServerCommandVerifier.verify(Self.lock, publicKey: Self.first, userID: Self.user, now: Self.now) == nil)
        #expect(ServerCommandVerifier.verify(Self.lock, publicKey: Self.second.publicKey, userID: "someoneelse", now: Self.now) == nil)
        #expect(ServerCommandVerifier.verify(Self.lock, publicKey: Self.second.publicKey, userID: Self.user, now: Date(timeIntervalSince1970: 3_000_000_000)) == nil)
    }

    @Test func tamperedPayloadFails() {
        var bytes = Data(base64Encoded: Self.lock.payload)!
        bytes[bytes.count - 2] ^= 1
        let tampered = SignedServerCommand(payload: bytes.base64EncodedString(), signature: Self.lock.signature)
        #expect(ServerCommandVerifier.verify(tampered, publicKey: Self.second.publicKey, userID: Self.user, now: Self.now) == nil)
    }

    @Test func fingerprintMatchesThePlugin() {
        #expect(ServerCommandVerifier.fingerprint(Self.second.publicKey) == Self.second.fingerprint)
    }
}

/// A key rotated twice while a device was away, a lock signed before the rotations (signed
/// again with each new key) and a lock for one device, all made by the plugin's own signer.
@Suite struct ServerKeyChainTests {
    static let first = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEd4ODUoIzPgbw+7C83az2+uXELKj1QUl+jeJNrowHBwQg7XXX6BKudnSD/ZoaZjF61JaihqXz9P4ark6f+rVSLQ=="
    static let current = ServerSigningKey(publicKey: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEaVxKIfDzsnjYXCqO88l9DiYduimGsEdV7fB0FFnmhTLTLWvo/mVIOrm+ZvM6nHRnmoywra+l7FZXZ5/bYZn6rA==", fingerprint: "28:8C:06:49:A9:8F:0A:60", previousPublicKey: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEdnlkagbbJrwF1fmD/y2ArWwUNh8BrdlAWXcfDsJTnMk4HB5Gz/LKQAuy1kAx8EVqXX+MyF+5zPnBL8rB7PANRA==", rotationSignature: "7q03LKVHOpJ2aGIpCy/yITJEtXzzlA3V4NL1p5BFNFL5Em4pVpwTAluoykdhrZqIS1VXXu1CbAsIAEDZssLdoQ==", chain: [
            ServerSigningKey(publicKey: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEdnlkagbbJrwF1fmD/y2ArWwUNh8BrdlAWXcfDsJTnMk4HB5Gz/LKQAuy1kAx8EVqXX+MyF+5zPnBL8rB7PANRA==", fingerprint: "CE:D3:2D:59:2B:48:C8:01", previousPublicKey: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEd4ODUoIzPgbw+7C83az2+uXELKj1QUl+jeJNrowHBwQg7XXX6BKudnSD/ZoaZjF61JaihqXz9P4ark6f+rVSLQ==", rotationSignature: "Ni3geSaFdY7aLdWzsQpsBsYgzk+1LQG/nBvc4XjNQchUSsoK3t1D/0Yh7tHnDfzYXawp4BRkBVPl8AFowxJ8kA=="),
            ServerSigningKey(publicKey: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEaVxKIfDzsnjYXCqO88l9DiYduimGsEdV7fB0FFnmhTLTLWvo/mVIOrm+ZvM6nHRnmoywra+l7FZXZ5/bYZn6rA==", fingerprint: "28:8C:06:49:A9:8F:0A:60", previousPublicKey: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEdnlkagbbJrwF1fmD/y2ArWwUNh8BrdlAWXcfDsJTnMk4HB5Gz/LKQAuy1kAx8EVqXX+MyF+5zPnBL8rB7PANRA==", rotationSignature: "7q03LKVHOpJ2aGIpCy/yITJEtXzzlA3V4NL1p5BFNFL5Em4pVpwTAluoykdhrZqIS1VXXu1CbAsIAEDZssLdoQ==")])
    static let userLock = SignedServerCommand(payload: "eyJ2IjoxLCJraW5kIjoibG9jayIsInVzZXIiOiIwZjhmYWQ1YmQ5Y2I0NjlmYTE2NTcwODY3NzI4OTUwZSIsInNlcnZlciI6InNlcnZlcmlkIiwiY291bnRlciI6MSwiaXNzdWVkIjoxODkzNDU2MDAwLCJleHBpcmVzIjoyMjA4ODE2MDAwfQ==", signature: "H8gxavKrn/duU/3VBxnHX40yhRLUgcJuz59CYkEemAMVWyB7CKi6CRDOUA/MwS0UrI0x6W3sVTG6f7I8aIcuQA==")
    static let deviceLock = SignedServerCommand(payload: "eyJ2IjoxLCJraW5kIjoibG9jayIsInVzZXIiOiIwZjhmYWQ1YmQ5Y2I0NjlmYTE2NTcwODY3NzI4OTUwZSIsInNlcnZlciI6InNlcnZlcmlkIiwiY291bnRlciI6MiwiaXNzdWVkIjoxODkzNDU2MDAwLCJleHBpcmVzIjoyMjA4ODE2MDAwLCJkZXZpY2UiOiJwaG9uZS0xIn0=", signature: "BrfsrDZ6HqFakLIhJBEmUfTiOKiHdf8L3B07b8bVRxpEfdMiTT2+Qsj19cuRic6ks9+P8aHfKz1psWspUF87GQ==")
    static let user = "0f8fad5b-d9cb-469f-a165-70867728950e"
    static let now = Date(timeIntervalSince1970: 1_893_456_100)

    @Test func followsEveryMissedRotation() {
        #expect(ServerCommandVerifier.decide(Self.current, pinned: Self.first) == .pin(Self.current.publicKey))
    }

    @Test func aBrokenLinkIsRefused() {
        var chain = Self.current.chain!
        chain.removeFirst()
        var gap = Self.current
        gap.chain = chain
        #expect(ServerCommandVerifier.decide(gap, pinned: Self.first) == .changed)
    }

    @Test func aLockSignedBeforeTheRotationsStillHolds() throws {
        let command = try #require(ServerCommandVerifier.verify(Self.userLock, publicKey: Self.current.publicKey, userID: Self.user, now: Self.now))
        #expect(command.device == nil)
        #expect(command.applies(toDevice: "anything"))
    }

    @Test func aDeviceLockIsOnlyForThatDevice() throws {
        let command = try #require(ServerCommandVerifier.verify(Self.deviceLock, publicKey: Self.current.publicKey, userID: Self.user, now: Self.now))
        #expect(command.applies(toDevice: "phone-1"))
        #expect(!command.applies(toDevice: "phone-2"))
    }
}
