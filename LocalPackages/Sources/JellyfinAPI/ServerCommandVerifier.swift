// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import CryptoKit

/// Checks the Arcfin Sync plugin's signed admin commands (clear a PIN, lock or unlock a profile)
/// against the server's public key, pinned the first time the app saw it. The plugin signs with
/// ECDSA P-256 and SHA-256 and sends the raw r‖s signature, which is what CryptoKit reads.
public enum ServerCommandVerifier {
    public struct Command: Sendable, Equatable, Decodable {
        public let kind: String
        /// Jellyfin user ID, without dashes.
        public let user: String
        public let server: String
        public let counter: Int64
        public let issued: Int64
        public let expires: Int64
        /// One device only, by its Jellyfin device ID; nil for all of the user's devices.
        public let device: String?
        /// A policy's rules, or why a lock was sent (reason: trust, pinTries, wipe); signed with the rest.
        public let data: [String: String]?

        public var commandKind: ServerCommandKind? { ServerCommandKind(rawValue: kind) }

        /// Meant for this device: all of the user's, or this one by ID.
        public func applies(toDevice deviceID: String) -> Bool { device == nil || device == deviceID }
    }

    public enum KeyDecision: Sendable, Equatable {
        /// Pin this key (the first one seen, or a rotation the pinned key signed).
        case pin(String)
        /// The pinned key still holds.
        case same
        /// A different key the pinned one didn't sign: don't trust it without the person saying so.
        case changed
    }

    public static func decide(_ key: ServerSigningKey, pinned: String?) -> KeyDecision {
        guard let pinned else { return publicKey(key.publicKey) == nil ? .changed : .pin(key.publicKey) }
        if pinned == key.publicKey { return .same }
        // Every link from the pinned key to the current one, each signed by the one before.
        let links = (key.chain?.isEmpty == false ? key.chain! : [key])
        guard links.last?.publicKey == key.publicKey else { return .changed }
        var trusted = pinned
        for link in links {
            guard link.previousPublicKey == trusted,
                  let signature = link.rotationSignature.flatMap({ Data(base64Encoded: $0) }),
                  let der = Data(base64Encoded: link.publicKey),
                  publicKey(link.publicKey) != nil,
                  verify(signature: signature, data: der, publicKey: trusted)
            else { return .changed }
            trusted = link.publicKey
        }
        return .pin(trusted)
    }

    /// The command, if its signature holds for `publicKey`, it's for `userID`, and it hasn't expired.
    public static func verify(_ command: SignedServerCommand, publicKey: String, userID: String, now: Date = .now) -> Command? {
        guard let payload = Data(base64Encoded: command.payload),
              let signature = Data(base64Encoded: command.signature),
              verify(signature: signature, data: payload, publicKey: publicKey),
              let decoded = try? JSONDecoder().decode(Command.self, from: payload),
              ArcfinCompanionClient.normalized(decoded.user) == ArcfinCompanionClient.normalized(userID),
              Double(decoded.expires) > now.timeIntervalSince1970
        else { return nil }
        return decoded
    }

    public static func fingerprint(_ publicKey: String) -> String? {
        guard let der = Data(base64Encoded: publicKey) else { return nil }
        return SHA256.hash(data: der).prefix(8).map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func publicKey(_ base64: String) -> P256.Signing.PublicKey? {
        Data(base64Encoded: base64).flatMap { try? P256.Signing.PublicKey(derRepresentation: $0) }
    }

    private static func verify(signature: Data, data: Data, publicKey base64: String) -> Bool {
        guard let key = publicKey(base64),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
        else { return false }
        return key.isValidSignature(signature, for: data)
    }
}
