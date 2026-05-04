import Foundation
import Telemetry

// MARK: - Server

public struct ServerCredential: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var baseURL: URL
    public var userID: String
    public var accessToken: String
    public var displayName: String

    public init(id: UUID = .init(), baseURL: URL, userID: String, accessToken: String, displayName: String) {
        self.id = id
        self.baseURL = baseURL
        self.userID = userID
        self.accessToken = accessToken
        self.displayName = displayName
    }
}

// MARK: - Keychain client

public protocol KeychainClientProtocol: Sendable {
    func save(_ credential: ServerCredential) throws
    func load(serverID: UUID) throws -> ServerCredential?
    func delete(serverID: UUID) throws
    func allServers() throws -> [ServerCredential]
}

// MARK: - Auth state

public enum AuthState: Sendable, Equatable {
    case unauthenticated
    case authenticated(ServerCredential)

    public var credential: ServerCredential? {
        if case .authenticated(let cred) = self { return cred }
        return nil
    }
}

// MARK: - Token refresh

public protocol TokenRefreshClientProtocol: Sendable {
    func refresh(credential: ServerCredential) async throws -> ServerCredential
}
