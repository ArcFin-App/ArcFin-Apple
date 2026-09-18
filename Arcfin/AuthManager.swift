import Foundation
import Observation
import AuthCore
import JellyfinAPI

@Observable
@MainActor
final class AuthManager {

    var state: AuthState = .unauthenticated
    var isChecking: Bool = true
    var profiles: [ServerCredential] = []

    let authClient = JellyfinAuthClient()
    private let keychain = KeychainStore()

    // MARK: - Startup

    func checkStoredAuth() async {
        defer { isChecking = false }
        let all = await backgroundKeychainRead()
        profiles = all
        guard !all.isEmpty else { return }
        let storedID = UserDefaults.standard.string(forKey: "arcfin.activeProfileID")
            .flatMap { UUID(uuidString: $0) }
        let candidate = all.first { $0.id == storedID } ?? all.first
        guard let cred = candidate else { return }
        guard await authClient.validateToken(credential: cred) else { return }
        state = .authenticated(cred)
        persist(active: cred)
    }

    // MARK: - Save & activate (initial sign-in)

    func save(_ credential: ServerCredential) {
        upsert(credential)
        persist(active: credential)
        state = .authenticated(credential)
    }

    // MARK: - Multi-profile management

    func addProfile(_ credential: ServerCredential) {
        upsert(credential)
        persist(active: credential)
        state = .authenticated(credential)
    }

    func switchTo(_ credential: ServerCredential) {
        persist(active: credential)
        state = .authenticated(credential)
    }

    func removeProfile(id: UUID) {
        let k = keychain
        Task.detached { try? k.delete(serverID: id); try? k.deletePin(for: id) }
        profiles.removeAll { $0.id == id }
        if case .authenticated(let current) = state, current.id == id {
            if let next = profiles.first {
                persist(active: next)
                state = .authenticated(next)
            } else {
                UserDefaults.standard.removeObject(forKey: "arcfin.activeProfileID")
                state = .unauthenticated
            }
        }
    }

    // MARK: - Sign out (removes current profile)

    func signOut() {
        if case .authenticated(let cred) = state {
            removeProfile(id: cred.id)
        }
    }

    // MARK: - PIN management

    func pin(for credentialID: UUID) async -> String? {
        let k = keychain
        return await Task.detached(priority: .userInitiated) {
            try? k.loadPin(for: credentialID)
        }.value
    }

    func savePin(_ pin: String, for credentialID: UUID) {
        let k = keychain
        Task.detached { try? k.savePin(pin, for: credentialID) }
    }

    func removePin(for credentialID: UUID) {
        let k = keychain
        Task.detached { try? k.deletePin(for: credentialID) }
    }

    // MARK: - Stored servers (async — always off main thread)

    func fetchStoredServers() async -> [ServerCredential] {
        await backgroundKeychainRead()
    }

    // MARK: - Private

    private func upsert(_ credential: ServerCredential) {
        let k = keychain
        Task.detached { try? k.save(credential) }
        if let idx = profiles.firstIndex(where: { $0.id == credential.id }) {
            profiles[idx] = credential
        } else {
            profiles.append(credential)
        }
    }

    private func persist(active credential: ServerCredential) {
        UserDefaults.standard.set(credential.id.uuidString, forKey: "arcfin.activeProfileID")
    }

    private func backgroundKeychainRead() async -> [ServerCredential] {
        let k = keychain
        return await Task.detached(priority: .userInitiated) {
            (try? k.allServers()) ?? []
        }.value
    }
}
