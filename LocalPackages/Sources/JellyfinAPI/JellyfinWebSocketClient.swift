// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// Anything Arcfin currently cares about from Jellyfin's WebSocket feed. Everything else
/// the server sends is intentionally not modeled.
public enum JellyfinWSEvent: Sendable {
    case syncPlayCommand(SyncPlayCommand)
    /// Fired for every SyncPlayGroupUpdate regardless of its nested Type — the payload
    /// shape of that nested Data varies by server version for some update kinds (e.g. who
    /// joined), so rather than parse each variant precisely, callers just treat this as
    /// "something about the group changed, go re-fetch /SyncPlay/List for current state".
    case syncPlayGroupChanged
    case syncPlayGroupGone
    /// Pushed by the server after `startSessionUpdates` — the same list GET /Sessions returns.
    case sessions([JellyfinSession])
    /// Watched state, progress, favourite or rating changed for these items, on any device.
    case userDataChanged(itemIds: [String])
    /// Titles were added to, removed from or updated in the library.
    case libraryChanged
}

/// Thin wrapper over URLSessionWebSocketTask for Jellyfin's `/socket` feed. One instance
/// per active connection; the owner (SyncPlayManager, AdminSessionsView, LiveUpdates) closes
/// it. `events` finishes when the connection drops, so an owner can reconnect.
public final class JellyfinWebSocketClient: NSObject, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let continuation: AsyncStream<JellyfinWSEvent>.Continuation
    private let keepAliveTask = KeepAliveBox()
    public let events: AsyncStream<JellyfinWSEvent>

    public init(credential: ServerCredential, deviceId: String) {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("socket"), resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.queryItems = [
            .init(name: "api_key", value: credential.accessToken),
            .init(name: "deviceId", value: deviceId),
        ]
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: comps.url!)
        (events, continuation) = AsyncStream.makeStream(of: JellyfinWSEvent.self)
        super.init()
        task.resume()
        Task { [weak self] in await self?.receiveLoop() }
    }

    public func close() {
        keepAliveTask.cancel()
        continuation.finish()
        task.cancel(with: .goingAway, reason: nil)
    }

    /// Asks the server to push the session list every `intervalMs`, starting immediately.
    public func startSessionUpdates(intervalMs: Int = 1000) {
        send(type: "SessionsStart", data: "0,\(intervalMs)")
    }

    public func stopSessionUpdates() {
        send(type: "SessionsStop", data: nil)
    }

    private func send(type: String, data: String?) {
        var payload: [String: String] = ["MessageType": type]
        payload["Data"] = data
        guard let json = try? JSONEncoder().encode(payload), let text = String(data: json, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func receiveLoop() async {
        while true {
            guard let message = try? await task.receive() else {
                keepAliveTask.cancel()
                continuation.finish()
                return
            }
            switch message {
            case .string(let text):
                handle(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) { handle(text) }
            @unknown default:
                continue
            }
        }
    }

    private func handle(_ text: String) {
        guard let raw = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: raw)
        else { return }
        switch envelope.messageType {
        case "SyncPlayCommand":
            guard let payload = try? JSONDecoder().decode(CommandPayload.self, from: raw),
                  let data = payload.data, let kind = SyncPlayCommand.Kind(rawValue: data.command)
            else { return }
            continuation.yield(.syncPlayCommand(SyncPlayCommand(kind: kind, positionTicks: data.positionTicks)))
        case "SyncPlayGroupUpdate":
            guard let payload = try? JSONDecoder().decode(GroupUpdatePayload.self, from: raw) else { return }
            if payload.data?.type == "GroupDoesNotExist" || payload.data?.type == "NotInGroup" {
                continuation.yield(.syncPlayGroupGone)
            } else {
                continuation.yield(.syncPlayGroupChanged)
            }
        case "Sessions":
            guard let payload = try? JSONDecoder().decode(SessionsPayload.self, from: raw) else { return }
            continuation.yield(.sessions(payload.data.map { $0.toSession() }))
        case "UserDataChanged":
            let ids = (try? JSONDecoder().decode(UserDataPayload.self, from: raw))?.data?.userDataList?.compactMap(\.itemId) ?? []
            continuation.yield(.userDataChanged(itemIds: ids))
        case "LibraryChanged":
            continuation.yield(.libraryChanged)
        case "ForceKeepAlive":
            // The server drops a socket that stays silent past this timeout (seconds).
            let timeout = (try? JSONDecoder().decode(KeepAlivePayload.self, from: raw))?.data ?? 60
            startKeepAlive(every: .seconds(max(timeout / 2, 5)))
        default:
            break
        }
    }

    private func startKeepAlive(every interval: Duration) {
        keepAliveTask.replace(with: Task { [weak self] in
            while !Task.isCancelled {
                self?.send(type: "KeepAlive", data: nil)
                try? await Task.sleep(for: interval)
            }
        })
    }

    private struct Envelope: Decodable {
        let messageType: String
        enum CodingKeys: String, CodingKey { case messageType = "MessageType" }
    }

    private struct CommandPayload: Decodable {
        struct Data: Decodable {
            let command: String
            let positionTicks: Int64?
            enum CodingKeys: String, CodingKey { case command = "Command"; case positionTicks = "PositionTicks" }
        }
        let data: Data?
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }

    private struct SessionsPayload: Decodable {
        let data: [SessionResponse]
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }

    private struct UserDataPayload: Decodable {
        struct Data: Decodable {
            struct Entry: Decodable {
                let itemId: String?
                enum CodingKeys: String, CodingKey { case itemId = "ItemId" }
            }
            let userDataList: [Entry]?
            enum CodingKeys: String, CodingKey { case userDataList = "UserDataList" }
        }
        let data: Data?
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }

    private struct KeepAlivePayload: Decodable {
        let data: Int?
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }

    private struct GroupUpdatePayload: Decodable {
        struct Data: Decodable {
            let type: String?
            enum CodingKeys: String, CodingKey { case type = "Type" }
        }
        let data: Data?
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }
}

private final class KeepAliveBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func replace(with new: Task<Void, Never>) {
        lock.withLock { task?.cancel(); task = new }
    }

    func cancel() {
        lock.withLock { task?.cancel(); task = nil }
    }
}
