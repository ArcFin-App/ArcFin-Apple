// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Models

public struct PickAvailability: Sendable, Decodable, Equatable {
    public let enabled: Bool
}

/// Who may use Pick Together on the server: on or off for everyone, and the users it's off for.
public struct PickTogetherAdminSettings: Sendable, Codable, Equatable {
    public var enabled: Bool
    public var disabledUsers: [String]

    public init(enabled: Bool = true, disabledUsers: [String] = []) {
        self.enabled = enabled
        self.disabledUsers = disabledUsers
    }
}

public enum PickOrder: String, Sendable, Codable, CaseIterable {
    case topRated = "TopRated", random = "Random", recentlyAdded = "RecentlyAdded"
}

public enum PickRule: String, Sendable, Codable, CaseIterable {
    case everyone = "Everyone", most = "Most"
}

public struct PickCreateBody: Sendable, Encodable {
    public var movies = true
    public var shows = false
    public var genres: [String] = []
    public var includeWatched = false
    public var order: PickOrder = .topRated
    public var rule: PickRule = .everyone
    /// Off by default: each person gets the titles in their own order.
    public var sameOrder = false

    public init() {}
}

public struct PickOptions: Sendable, Decodable, Equatable {
    public let movies: Bool
    public let shows: Bool
    public let genres: [String]
    public let includeWatched: Bool
    public let order: String
    public let rule: String
    public let sameOrder: Bool
}

public struct PickPerson: Sendable, Decodable, Equatable, Hashable, Identifiable {
    /// Only for the host to remove this person; it says nothing about their device.
    public let id: String
    public let isHost: Bool
    public let name: String
    public let isMe: Bool
    public let isAway: Bool
    public let swiped: Int
    public let total: Int
}

public struct PickCard: Sendable, Decodable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let type: String
    public let year: Int?
    public let rating: Double?
    public let officialRating: String?
    public let overview: String
    public let runtimeMinutes: Int?
    public let genres: [String]

    public var isShow: Bool { type == "Series" }
}

public struct PickMatch: Sendable, Decodable, Equatable, Hashable, Identifiable {
    public let item: PickCard
    public let round: Int
    public let at: Date

    public var id: String { "\(round)-\(item.id)" }
}

/// Watching a match together over SyncPlay. The first person in leads: their device makes the
/// SyncPlay group once everyone here is in, and the others join it.
public struct PickTogetherPlan: Sendable, Decodable, Equatable {
    public let itemId: String
    public let iAmIn: Bool
    public let iAmLeader: Bool
    public let ready: Bool
    public let waiting: [String]
    public let groupId: String?
    public let playItemId: String?
    public let startTicks: Int64
}

public struct PickSessionState: Sendable, Decodable, Equatable {
    public let code: String
    public let round: Int
    public let isHost: Bool
    /// No one new can join, even with the code.
    public let locked: Bool
    public let options: PickOptions
    public let people: [PickPerson]
    public let cards: [PickCard]
    public let remaining: Int
    public let matches: [PickMatch]
    public let together: PickTogetherPlan?
}

/// A failed call, with the plugin's own message when it gave one ("This session has ended.").
public struct PickTogetherError: Error, Sendable, LocalizedError {
    public let status: Int
    public let message: String?

    public var errorDescription: String? { message }
}

// MARK: - Client

/// Pick Together, served by the Arcfin Sync plugin under ArcfinSync/PickTogether. Sessions live
/// on the server, so everyone in one has to be signed in to the same server.
public struct PickTogetherClient: Sendable {
    public init() {}

    public func availability(credential: ServerCredential, authHeader: String) async throws -> PickAvailability {
        try await send("GET", "", credential: credential, authHeader: authHeader)
    }

    public func create(_ body: PickCreateBody, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        try await send("POST", "/Sessions", body: body, credential: credential, authHeader: authHeader)
    }

    public func join(code: String, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        try await send("POST", "/Sessions/\(Self.component(code))/Join", credential: credential, authHeader: authHeader)
    }

    public func state(code: String, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        try await send("GET", "/Sessions/\(Self.component(code))", credential: credential, authHeader: authHeader)
    }

    public func swipe(code: String, itemID: String, like: Bool, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        struct Body: Encodable { let itemId: String; let like: Bool }
        return try await send("POST", "/Sessions/\(Self.component(code))/Swipe", body: Body(itemId: itemID, like: like),
                              credential: credential, authHeader: authHeader)
    }

    public func watchTogether(code: String, itemID: String, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        struct Body: Encodable { let itemId: String }
        return try await send("POST", "/Sessions/\(Self.component(code))/Together", body: Body(itemId: itemID),
                              credential: credential, authHeader: authHeader)
    }

    public func notTogether(code: String, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        try await send("DELETE", "/Sessions/\(Self.component(code))/Together", credential: credential, authHeader: authHeader)
    }

    /// The leader's device made the SyncPlay group: what it plays, from where, for the others to join.
    public func togetherGroup(code: String, groupID: String, playItemID: String, startTicks: Int64,
                              credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        struct Body: Encodable { let groupId: String; let playItemId: String; let startTicks: Int64 }
        return try await send("POST", "/Sessions/\(Self.component(code))/Together/Group",
                              body: Body(groupId: groupID, playItemId: playItemID, startTicks: startTicks),
                              credential: credential, authHeader: authHeader)
    }

    /// The host stops new people joining, or lets them again.
    public func lock(code: String, locked: Bool, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        struct Body: Encodable { let locked: Bool }
        return try await send("POST", "/Sessions/\(Self.component(code))/Lock", body: Body(locked: locked),
                              credential: credential, authHeader: authHeader)
    }

    /// The host takes someone out; that device can't join this session again.
    public func remove(code: String, personID: String, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        try await send("DELETE", "/Sessions/\(Self.component(code))/People/\(Self.component(personID))",
                       credential: credential, authHeader: authHeader)
    }

    public func restart(code: String, credential: ServerCredential, authHeader: String) async throws -> PickSessionState {
        try await send("POST", "/Sessions/\(Self.component(code))/Restart", credential: credential, authHeader: authHeader)
    }

    public func leave(code: String, credential: ServerCredential, authHeader: String) async {
        let _: Empty? = try? await send("DELETE", "/Sessions/\(Self.component(code))/Me", credential: credential, authHeader: authHeader)
    }

    /// What a session's QR code holds: just the code, so nothing about the server is shared. The
    /// Camera app opens it in Arcfin, and Pick Together's own scanner reads it too.
    public static func joinLink(code: String) -> URL {
        URL(string: "arcfin://pick/\(component(code))")!
    }

    /// The code in a scanned QR code or a typed one: an arcfin://pick/<code> link, or the code itself.
    public static func code(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "arcfin", url.host == "pick" {
            return url.pathComponents.dropFirst().first?.uppercased()
        }
        let code = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        return (4...12).contains(code.count) && code.count == trimmed.count ? code : nil
    }

    // MARK: Admin

    public func adminSettings(credential: ServerCredential, authHeader: String) async throws -> PickTogetherAdminSettings {
        try await send("GET", "", base: "ArcfinSync/Admin/PickTogether", credential: credential, authHeader: authHeader)
    }

    public func saveAdminSettings(_ settings: PickTogetherAdminSettings, credential: ServerCredential, authHeader: String) async throws -> PickTogetherAdminSettings {
        try await send("PUT", "", base: "ArcfinSync/Admin/PickTogether", body: settings, credential: credential, authHeader: authHeader)
    }

    // MARK: Plumbing

    private struct Empty: Decodable {}

    private func send<T: Decodable>(_ method: String, _ path: String, base: String = "ArcfinSync/PickTogether",
                                    body: (any Encodable)? = nil,
                                    credential: ServerCredential, authHeader: String) async throws -> T {
        guard let url = URL(string: "\(base)\(path)", relativeTo: Self.directory(credential.baseURL)) else {
            throw PickTogetherError(status: 0, message: nil)
        }
        var req = URLRequest(url: url.absoluteURL)
        req.httpMethod = method
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .custom { keys in PascalKey(keys.last!.stringValue.prefix(1).uppercased() + keys.last!.stringValue.dropFirst()) }
            req.httpBody = try encoder.encode(body)
        }
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            // ASP.NET wraps a plain message in quotes as JSON; a problem document isn't one to show.
            let message = text.flatMap { $0.hasPrefix("{") ? nil : $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            throw PickTogetherError(status: status, message: message?.isEmpty == false ? message : nil)
        }
        if T.self == Empty.self { return Empty() as! T }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in PascalKey(keys.last!.stringValue.prefix(1).lowercased() + keys.last!.stringValue.dropFirst()) }
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            return Self.date(raw) ?? .now
        }
        return try decoder.decode(T.self, from: data)
    }

    private struct PascalKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static func date(_ raw: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return full.date(from: raw) ?? plain.date(from: raw) ?? plain.date(from: raw + "Z")
    }

    private static func component(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    private static func directory(_ base: URL) -> URL {
        base.absoluteString.hasSuffix("/") ? base : URL(string: base.absoluteString + "/") ?? base
    }
}
