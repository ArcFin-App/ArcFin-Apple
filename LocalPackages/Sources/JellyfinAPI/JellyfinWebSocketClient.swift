// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// Anything Arcfin currently cares about from Jellyfin's WebSocket feed. Everything else
/// the server sends (library change notifications, generic session updates, etc.) is
/// intentionally not modeled — SyncPlay is the only consumer today.
public enum JellyfinWSEvent: Sendable {
    case syncPlayCommand(SyncPlayCommand)
    /// Fired for every SyncPlayGroupUpdate regardless of its nested Type — the payload
    /// shape of that nested Data varies by server version for some update kinds (e.g. who
    /// joined), so rather than parse each variant precisely, callers just treat this as
    /// "something about the group changed, go re-fetch /SyncPlay/List for current state".
    case syncPlayGroupChanged
    case syncPlayGroupGone
}

/// Thin wrapper over URLSessionWebSocketTask for Jellyfin's `/socket` feed. One instance
/// per active connection — SyncPlayManager owns its lifecycle (connect only while a
/// SyncPlay group is joined, disconnect on leave).
public final class JellyfinWebSocketClient: NSObject, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let continuation: AsyncStream<JellyfinWSEvent>.Continuation
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
        continuation.finish()
        task.cancel(with: .goingAway, reason: nil)
    }

    private func receiveLoop() async {
        while true {
            guard let message = try? await task.receive() else { return }
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
        default:
            break
        }
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

    private struct GroupUpdatePayload: Decodable {
        struct Data: Decodable {
            let type: String?
            enum CodingKeys: String, CodingKey { case type = "Type" }
        }
        let data: Data?
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }
}
