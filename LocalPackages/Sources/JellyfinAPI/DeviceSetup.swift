// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network

/// Setting up an Apple TV from an iPhone or iPad on the same network. The Apple TV advertises
/// itself; the phone connects and says which server and account to use; the Apple TV asks
/// the person in front of it, starts Quick Connect and shows its code; the phone shows the
/// same code and, once confirmed, approves it with its own sign-in. Only a server address
/// and a Quick Connect code cross the network, never a password, token or header.
public enum DeviceSetup {
    public static let serviceType = "_arcfin-setup._tcp"
    /// A message is a few hundred bytes; anything far bigger isn't from Arcfin.
    static let maxMessageSize = 16 * 1024

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

    /// A profile to sign the Apple TV in with: who, and its server's addresses, best first.
    public struct Profile: Codable, Equatable, Sendable {
        public let userName: String
        public let serverName: String
        public let servers: [String]

        public init(userName: String, serverName: String, servers: [String]) {
            self.userName = userName
            self.serverName = serverName
            self.servers = servers
        }
    }

    public enum Message: Codable, Equatable, Sendable {
        /// Phone → TV: the profiles to sign in, the one to use first.
        case hello(profiles: [Profile])
        /// TV → phone: the person at the TV allowed it; it's contacting the servers.
        case allowed
        /// TV → phone: the Quick Connect code for `profile` (an index into hello's list). The
        /// first is shown on the TV and checked by the person; the rest follow over the same
        /// connection.
        case code(profile: Int, code: String)
        /// TV → phone: that profile couldn't be started (server unreachable or Quick Connect
        /// off); the others carry on.
        case skipped(profile: Int, Failure)
        /// Phone → TV: that profile's code was approved.
        case approved(profile: Int)
        /// TV → phone: signed in, with how many profiles.
        case done(signedIn: Int)
        /// Either way: it stopped, and why.
        case failed(Failure)
    }

    /// Newline-separated JSON, one message per line.
    struct Framer {
        private var buffer = Data()

        enum FramingError: Error { case tooLarge }

        mutating func append(_ data: Data) throws -> [Message] {
            buffer.append(data)
            var messages: [Message] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let message = try? JSONDecoder().decode(Message.self, from: Data(line)) {
                    messages.append(message)
                }
            }
            if buffer.count > DeviceSetup.maxMessageSize { throw FramingError.tooLarge }
            return messages
        }

        static func encode(_ message: Message) -> Data {
            var data = (try? JSONEncoder().encode(message)) ?? Data()
            data.append(0x0A)
            return data
        }
    }
}

/// One setup conversation over a local TCP connection. `messages` finishes when the other
/// side goes away or sends something that isn't a setup message.
public final class DeviceSetupChannel: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "arcfin.device-setup.channel")
    private var framer = DeviceSetup.Framer()
    private let continuation: AsyncStream<DeviceSetup.Message>.Continuation
    public let messages: AsyncStream<DeviceSetup.Message>

    init(connection: NWConnection) {
        self.connection = connection
        (messages, continuation) = AsyncStream.makeStream(of: DeviceSetup.Message.self)
        connection.stateUpdateHandler = { [continuation] state in
            switch state {
            case .failed, .cancelled: continuation.finish()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    /// Connects to an Apple TV found by `DeviceSetupBrowser`.
    public convenience init(endpoint: NWEndpoint) {
        self.init(connection: NWConnection(to: endpoint, using: .tcp))
    }

    public func send(_ message: DeviceSetup.Message) {
        connection.send(content: DeviceSetup.Framer.encode(message), completion: .contentProcessed { _ in })
    }

    public func close() {
        connection.cancel()
        continuation.finish()
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

/// The Apple TV's side: advertises it on the local network and hands over each phone that
/// connects.
public final class DeviceSetupListener: @unchecked Sendable {
    private let listener: NWListener
    private let continuation: AsyncStream<DeviceSetupChannel>.Continuation
    public let channels: AsyncStream<DeviceSetupChannel>

    /// `port` is only for tests; the real listener takes any free port and is found by name.
    public init(advertised: Bool = true, port: NWEndpoint.Port = .any) throws {
        listener = try NWListener(using: .tcp, on: port)
        (channels, continuation) = AsyncStream.makeStream(of: DeviceSetupChannel.self)
        if advertised { listener.service = NWListener.Service(type: DeviceSetup.serviceType) }
        listener.newConnectionHandler = { [continuation] connection in
            continuation.yield(DeviceSetupChannel(connection: connection))
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
