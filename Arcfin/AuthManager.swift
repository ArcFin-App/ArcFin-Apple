import Foundation
import Observation
import AuthCore
import JellyfinAPI

@Observable
@MainActor
final class AuthManager {

    var state: AuthState = .unauthenticated
    var isChecking: Bool = true

    let authClient = JellyfinAuthClient()
    private let keychain = KeychainStore()

    // MARK: - Startup

    func checkStoredAuth() async {
        defer { isChecking = false }
        // SecItemCopyMatching is blocking — run on background thread
        let servers = await backgroundKeychainRead()
        guard let credential = servers.first else { return }
        guard await authClient.validateToken(credential: credential) else { return }
        state = .authenticated(credential)
    }

    // MARK: - Save & activate

    func save(_ credential: ServerCredential) {
        let k = keychain
        Task.detached { try? k.save(credential) }
        state = .authenticated(credential)
    }

    // MARK: - Sign out

    func signOut() {
        if case .authenticated(let cred) = state {
            let k = keychain
            let id = cred.id
            Task.detached { try? k.delete(serverID: id) }
        }
        state = .unauthenticated
    }

    // MARK: - Stored servers (async — always off main thread)

    func fetchStoredServers() async -> [ServerCredential] {
        await backgroundKeychainRead()
    }

    // MARK: - Private

    private func backgroundKeychainRead() async -> [ServerCredential] {
        let k = keychain
        return await Task.detached(priority: .userInitiated) {
            (try? k.allServers()) ?? []
        }.value
    }
}
