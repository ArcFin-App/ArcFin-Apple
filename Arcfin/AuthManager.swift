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
        guard let credential = (try? keychain.allServers())?.first else { return }
        guard await authClient.validateToken(credential: credential) else { return }
        state = .authenticated(credential)
    }

    // MARK: - Save & activate

    func save(_ credential: ServerCredential) {
        try? keychain.save(credential)
        state = .authenticated(credential)
    }

    // MARK: - Sign out

    func signOut() {
        if case .authenticated(let cred) = state {
            try? keychain.delete(serverID: cred.id)
        }
        state = .unauthenticated
    }

    // MARK: - Stored servers (for UI)

    var storedServers: [ServerCredential] {
        (try? keychain.allServers()) ?? []
    }
}
