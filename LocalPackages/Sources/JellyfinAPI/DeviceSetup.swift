// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation
import Network

/// Setting up an Apple TV from an iPhone or iPad on the same network (#481).
///
/// The two first agree on keys, the way Bluetooth numeric comparison does: the Apple TV
/// commits to a fresh X25519 key, the phone sends its own, the Apple TV reveals its key, and
/// both work out the same secret. A six-digit code made from that secret and both keys is
/// shown on both screens; someone in the middle ends up with different keys, so different
/// codes. The Apple TV commits first so a device posing as a phone can't work out the code
/// before it has sent its key: every try puts a code on the TV's screen, where it's seen, and
/// the TV takes one try at a time with a pause between them. The phone only connects when
/// someone taps Set Up. Nothing else is sent until the person has pressed Allow on the TV and
/// confirmed the code on the phone.
/// After that every message is sealed with ChaCha20-Poly1305, with a key for each direction
/// and a counter as the nonce, so a changed, replayed or reordered message ends the session.
public enum DeviceSetup {
    public static let serviceType = "_arcfin-setup._tcp"
    /// A message is a few hundred bytes; anything far bigger isn't from Arcfin.
    static let maxMessageSize = 16 * 1024
    /// How long the Apple TV waits after one exchange before taking the next.
    static let pauseBetweenTries: Duration = .seconds(2)

    public enum Failure: String, Codable, Sendable {
        /// The person at the Apple TV said no, or the phone cancelled.
        case declined
        /// None of the addresses answered from the Apple TV.
        case unreachable
        /// The server answered but has Quick Connect turned off.
        case quickConnectOff
        /// Another phone is already setting this Apple TV up.
        case busy
        /// The code ran out before it was approved.
        case expired
    }

    /// A profile to sign the Apple TV in with: who, its server's addresses best first, and
    /// its TMDB key when it has one.
    public struct Profile: Codable, Equatable, Sendable {
        public let userName: String
        public let serverName: String
        public let servers: [String]
        public let tmdbKey: String?

        public init(userName: String, serverName: String, servers: [String], tmdbKey: String? = nil) {
            self.userName = userName
            self.serverName = serverName
            self.servers = servers
            self.tmdbKey = tmdbKey
        }
    }

    /// What the two say once the code is confirmed. Only ever sent sealed.
    public enum Message: Codable, Equatable, Sendable {
        /// Phone → TV, once the person there confirmed the code and picked them: the profiles
        /// to sign in, the one to use first.
        case hello(profiles: [Profile])
        /// TV → phone: the person at the TV pressed Allow. `signedIn` is the Jellyfin user ids
        /// already on the TV, so the phone doesn't offer them again; sent only after Allow, so
        /// nobody can connect just to learn who uses this Apple TV.
        case allowed(signedIn: [String])
        /// TV → phone: the Quick Connect code for `profile` (an index into hello's list).
        case code(profile: Int, code: String)
        /// TV → phone: that profile couldn't be started; the others carry on.
        case skipped(profile: Int, Failure)
        /// Phone → TV: that profile's code was approved.
        case approved(profile: Int)
        /// TV → phone: signed in, with how many profiles.
        case done(signedIn: Int)
        /// Either way: it stopped, and why.
        case failed(Failure)
    }

    /// What goes over the connection: the key exchange in the clear, then sealed messages.
    enum Wire: Codable, Equatable {
        /// TV → phone, first: SHA-256 of the TV's public key and a random nonce.
        case commit(Data)
        /// Phone → TV: the phone's public key.
        case key(Data)
        /// TV → phone: the TV's public key and nonce, which must match the commitment.
        case reveal(key: Data, nonce: Data)
        /// A Message, sealed.
        case sealed(Data)
    }

    /// Newline-separated JSON, one wire message per line.
    struct Framer {
        private var buffer = Data()

        enum FramingError: Error { case tooLarge }

        mutating func append(_ data: Data) throws -> [Wire] {
            buffer.append(data)
            var messages: [Wire] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let message = try? JSONDecoder().decode(Wire.self, from: Data(line)) {
                    messages.append(message)
                }
            }
            if buffer.count > DeviceSetup.maxMessageSize { throw FramingError.tooLarge }
            return messages
        }

        static func encode(_ message: Wire) -> Data {
            var data = (try? JSONEncoder().encode(message)) ?? Data()
            data.append(0x0A)
            return data
        }
    }

    /// The keys and code both sides derive from the exchange.
    struct Keys {
        let phoneToTV: SymmetricKey
        let tvToPhone: SymmetricKey
        let code: String

        init(secret: SharedSecret, phoneKey: Data, tvKey: Data) {
            let salt = phoneKey + tvKey
            func derive(_ info: String, _ bytes: Int) -> SymmetricKey {
                secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data(info.utf8), outputByteCount: bytes)
            }
            phoneToTV = derive("arcfin-setup phone to tv", 32)
            tvToPhone = derive("arcfin-setup tv to phone", 32)
            let digits = derive("arcfin-setup code", 8).withUnsafeBytes { raw in
                raw.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            } % 1_000_000
            code = String(format: "%06llu", digits)
        }
    }

    static func commitment(key: Data, nonce: Data) -> Data {
        Data(SHA256.hash(data: key + nonce))
    }

    /// Seals and opens messages in one direction each, with a counter for the nonce.
    struct Cipher {
        private let sendKey: SymmetricKey
        private let receiveKey: SymmetricKey
        private var sent: UInt64 = 0
        private var received: UInt64 = 0

        init(send: SymmetricKey, receive: SymmetricKey) {
            sendKey = send
            receiveKey = receive
        }

        enum CipherError: Error { case badMessage }

        private static func nonce(_ counter: UInt64) throws -> ChaChaPoly.Nonce {
            var bytes = Data(count: 4)
            withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
            return try ChaChaPoly.Nonce(data: bytes)
        }

        mutating func seal(_ message: Message) throws -> Data {
            let plain = try JSONEncoder().encode(message)
            let box = try ChaChaPoly.seal(plain, using: sendKey, nonce: Self.nonce(sent))
            sent += 1
            return box.ciphertext + box.tag
        }

        /// Throws for anything changed, replayed or out of order.
        mutating func open(_ sealed: Data) throws -> Message {
            guard sealed.count >= 16 else { throw CipherError.badMessage }
            let box = try ChaChaPoly.SealedBox(nonce: Self.nonce(received),
                                               ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
            let plain = try ChaChaPoly.open(box, using: receiveKey)
            received += 1
            return try JSONDecoder().decode(Message.self, from: plain)
        }
    }
}

/// One local TCP connection carrying wire messages. `messages` finishes when the other side
/// goes away or sends something that isn't a setup message.
final class DeviceSetupChannel: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "arcfin.device-setup.channel")
    private var framer = DeviceSetup.Framer()
    private let continuation: AsyncStream<DeviceSetup.Wire>.Continuation
    let messages: AsyncStream<DeviceSetup.Wire>

    init(connection: NWConnection) {
        self.connection = connection
        (messages, continuation) = AsyncStream.makeStream(of: DeviceSetup.Wire.self)
        connection.stateUpdateHandler = { [continuation] state in
            switch state {
            case .failed, .cancelled: continuation.finish()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func send(_ message: DeviceSetup.Wire) {
        connection.send(content: DeviceSetup.Framer.encode(message), completion: .contentProcessed { _ in })
    }

    func close() {
        connection.cancel()
        continuation.finish()
    }

    /// Sends a last message and closes once it's gone: closing straight after `send` drops
    /// what hasn't been sent yet.
    func finish(with message: DeviceSetup.Wire) {
        connection.send(content: DeviceSetup.Framer.encode(message), completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for message in try self.framer.append(data) { self.continuation.yield(message) }
                } catch {
                    self.close()
                    return
                }
            }
            if isComplete || error != nil {
                self.close()
                return
            }
            self.receive()
        }
    }
}

/// A setup conversation: the key exchange, then sealed messages. `code` is shown on both
/// screens; anything that doesn't open, or arrives out of turn, ends the session.
public final class DeviceSetupSession: @unchecked Sendable {
    public enum HandshakeError: Error { case closed, wrongCommitment, badKey }

    private enum Role { case phone, tv }

    /// The six digits both screens show; they match only if nobody is in between.
    public private(set) var code = ""
    public let messages: AsyncStream<DeviceSetup.Message>
    /// Finishes when the connection closes, from either side.
    public let closed: AsyncStream<Void>

    private let channel: DeviceSetupChannel
    private let role: Role
    private let lock = NSLock()
    private var cipher: DeviceSetup.Cipher?
    private var handshake: CheckedContinuation<Void, Error>?
    private let messageContinuation: AsyncStream<DeviceSetup.Message>.Continuation
    private let closedContinuation: AsyncStream<Void>.Continuation

    private init(channel: DeviceSetupChannel, role: Role) {
        self.channel = channel
        self.role = role
        (messages, messageContinuation) = AsyncStream.makeStream(of: DeviceSetup.Message.self)
        (closed, closedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    /// The phone's side: connects to an Apple TV found by `DeviceSetupBrowser`.
    public static func connect(to endpoint: NWEndpoint) async throws -> DeviceSetupSession {
        try await start(DeviceSetupChannel(connection: NWConnection(to: endpoint, using: .tcp)), role: .phone)
    }

    /// The Apple TV's side, for a phone that connected to `DeviceSetupListener`.
    static func accept(_ channel: DeviceSetupChannel) async throws -> DeviceSetupSession {
        try await start(channel, role: .tv)
    }

    static func phoneHandshake(_ channel: DeviceSetupChannel) async throws -> DeviceSetupSession {
        try await start(channel, role: .phone)
    }

    private static func start(_ channel: DeviceSetupChannel, role: Role) async throws -> DeviceSetupSession {
        let session = DeviceSetupSession(channel: channel, role: role)
        do {
            try await withCheckedThrowingContinuation { continuation in
                session.lock.withLock { session.handshake = continuation }
                Task { await session.run() }
            }
            return session
        } catch {
            session.close()
            throw error
        }
    }

    /// One loop for the whole conversation: the exchange in order, then sealed messages.
    private func run() async {
        let mine = Curve25519.KeyAgreement.PrivateKey()
        let myKey = mine.publicKey.rawRepresentation
        let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        var commitment: Data?
        if role == .tv { channel.send(.commit(DeviceSetup.commitment(key: myKey, nonce: nonce))) }

        var failure: HandshakeError = .closed
        loop: for await wire in channel.messages {
            let agreed = lock.withLock { cipher != nil }
            switch (role, wire, agreed) {
            case (.phone, .commit(let value), false) where commitment == nil:
                commitment = value
                channel.send(.key(myKey))
            case (.tv, .key(let phoneKey), false):
                channel.send(.reveal(key: myKey, nonce: nonce))
                guard agree(mine, theirs: phoneKey, phoneKey: phoneKey, tvKey: myKey) else { failure = .badKey; break loop }
            case (.phone, .reveal(let tvKey, let tvNonce), false):
                guard let commitment, DeviceSetup.commitment(key: tvKey, nonce: tvNonce) == commitment else {
                    failure = .wrongCommitment
                    break loop
                }
                guard agree(mine, theirs: tvKey, phoneKey: myKey, tvKey: tvKey) else { failure = .badKey; break loop }
            case (_, .sealed(let data), true):
                guard let message = open(data) else { break loop }
                messageContinuation.yield(message)
            default:
                break loop
            }
        }
        lock.withLock { handshake }?.resume(throwing: failure)
        lock.withLock { handshake = nil }
        close()
    }

    private func agree(_ mine: Curve25519.KeyAgreement.PrivateKey, theirs: Data, phoneKey: Data, tvKey: Data) -> Bool {
        guard let theirKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs),
              let secret = try? mine.sharedSecretFromKeyAgreement(with: theirKey)
        else { return false }
        let keys = DeviceSetup.Keys(secret: secret, phoneKey: phoneKey, tvKey: tvKey)
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            code = keys.code
            cipher = role == .phone
                ? DeviceSetup.Cipher(send: keys.phoneToTV, receive: keys.tvToPhone)
                : DeviceSetup.Cipher(send: keys.tvToPhone, receive: keys.phoneToTV)
            defer { handshake = nil }
            return handshake
        }
        waiting?.resume()
        return true
    }

    public func send(_ message: DeviceSetup.Message) {
        guard let sealed = seal(message) else { return }
        channel.send(.sealed(sealed))
    }

    /// Sends a last message and closes once it's gone.
    public func finish(with message: DeviceSetup.Message) {
        guard let sealed = seal(message) else { return close() }
        channel.finish(with: .sealed(sealed))
    }

    public func close() {
        channel.close()
        messageContinuation.finish()
        closedContinuation.finish()
    }

    private func seal(_ message: DeviceSetup.Message) -> Data? {
        lock.withLock { try? cipher?.seal(message) }
    }

    private func open(_ data: Data) -> DeviceSetup.Message? {
        lock.withLock { try? cipher?.open(data) }
    }
}

/// The Apple TV's side: advertises it on the local network and hands over each phone that
/// connects, once the keys are agreed.
public final class DeviceSetupListener: @unchecked Sendable {
    private let listener: NWListener
    private let continuation: AsyncStream<DeviceSetupSession>.Continuation
    public let sessions: AsyncStream<DeviceSetupSession>

    /// `port` is only for tests; the real listener takes any free port and is found by name.
    public init(advertised: Bool = true, port: NWEndpoint.Port = .any) throws {
        listener = try NWListener(using: .tcp, on: port)
        (sessions, continuation) = AsyncStream.makeStream(of: DeviceSetupSession.self)
        if advertised { listener.service = NWListener.Service(type: DeviceSetup.serviceType) }
        let gate = HandshakeGate()
        listener.newConnectionHandler = { [continuation] connection in
            // One exchange at a time, with a pause after each: a device can't run many in
            // parallel or back to back to look for a code that matches.
            guard gate.enter() else {
                connection.cancel()
                return
            }
            let channel = DeviceSetupChannel(connection: connection)
            Task {
                // A connection that doesn't finish the exchange within a few seconds is dropped.
                let timeout = Task {
                    // Cancelled once the exchange is done; only a real timeout closes it.
                    guard (try? await Task.sleep(for: .seconds(10))) != nil else { return }
                    channel.close()
                }
                let session = try? await DeviceSetupSession.accept(channel)
                timeout.cancel()
                if let session { continuation.yield(session) } else { channel.close() }
                try? await Task.sleep(for: DeviceSetup.pauseBetweenTries)
                gate.leave()
            }
        }
        listener.stateUpdateHandler = { [continuation] state in
            if case .failed = state { continuation.finish() }
        }
        listener.start(queue: DispatchQueue(label: "arcfin.device-setup.listener"))
    }

    public var port: NWEndpoint.Port? { listener.port }

    public func stop() {
        listener.cancel()
        continuation.finish()
    }
}

/// Lets one key exchange through at a time.
private final class HandshakeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    func enter() -> Bool {
        lock.withLock {
            guard !busy else { return false }
            busy = true
            return true
        }
    }

    func leave() {
        lock.withLock { busy = false }
    }
}

/// The phone's side: the Apple TVs on the local network waiting to be set up.
public final class DeviceSetupBrowser: @unchecked Sendable {
    public struct AppleTV: Hashable, Sendable {
        public let name: String
        public let endpoint: NWEndpoint
    }

    private let browser: NWBrowser
    private let continuation: AsyncStream<[AppleTV]>.Continuation
    public let results: AsyncStream<[AppleTV]>

    public init() {
        browser = NWBrowser(for: .bonjour(type: DeviceSetup.serviceType, domain: nil), using: .tcp)
        (results, continuation) = AsyncStream.makeStream(of: [AppleTV].self)
        browser.browseResultsChangedHandler = { [continuation] results, _ in
            continuation.yield(results.compactMap { result in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return AppleTV(name: name, endpoint: result.endpoint)
            })
        }
        browser.stateUpdateHandler = { [continuation] state in
            if case .failed = state { continuation.finish() }
        }
        browser.start(queue: DispatchQueue(label: "arcfin.device-setup.browser"))
    }

    public func stop() {
        browser.cancel()
        continuation.finish()
    }
}
