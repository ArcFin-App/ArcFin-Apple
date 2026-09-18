import Foundation
import Observation
import AuthCore
import JellyfinAPI
#if os(iOS)
import NetworkExtension
import CoreLocation
#endif

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
        guard var cred = candidate else { return }

        // Local/Remote URL switching only takes effect on a fresh launch — resolve once here.
        let resolvedURL = await Self.resolveBaseURL(for: cred.baseURL)
        if resolvedURL != cred.baseURL {
            cred.baseURL = resolvedURL
            upsert(cred)
        }

        guard await authClient.validateToken(credential: cred) else { return }
        // Backfills the avatar tag for credentials saved before it existed, and picks up
        // any server-side avatar change — cheap, and only happens once per cold launch.
        if let tag = await authClient.fetchUserImageTag(credential: cred), tag != cred.userImageTag {
            cred.userImageTag = tag
            upsert(cred)
        }
        state = .authenticated(cred)
        persist(active: cred)
    }

    // MARK: - Local/Remote server URL resolution

    /// Picks the Local URL when the device is on the saved home Wi-Fi network,
    /// otherwise falls back to the Remote URL, otherwise leaves the URL unchanged.
    static func resolveBaseURL(for original: URL) async -> URL {
        #if os(iOS)
        let defaults = UserDefaults.standard
        guard let localString = defaults.string(forKey: "serverLocalURL"), !localString.isEmpty,
              let localURL = URL(string: localString),
              let savedSSID = defaults.string(forKey: "serverHomeSSID"), !savedSSID.isEmpty
        else { return original }

        let currentSSID = await currentWiFiSSID()
        if currentSSID == savedSSID { return localURL }

        if let remoteString = defaults.string(forKey: "serverRemoteURL"), !remoteString.isEmpty,
           let remoteURL = URL(string: remoteString) {
            return remoteURL
        }
        return original
        #else
        return original
        #endif
    }

    static func currentWiFiSSID() async -> String? {
        #if os(iOS)
        // Undocumented but widely-reported: NEHotspotNetwork.fetchCurrent silently
        // fails ("invalid result code 1") without Location authorization too, despite
        // Apple's docs saying the Access Wi-Fi Information capability alone suffices.
        await LocationAuthWaiter().wait()
        return await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.ssid)
            }
        }
        #else
        nil
        #endif
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

#if os(iOS)
/// Requests When In Use location authorization if not yet determined, and waits for
/// the user's decision before returning — NEHotspotNetwork.fetchCurrent needs it granted.
@MainActor
private final class LocationAuthWaiter: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation?.resume()
        continuation = nil
    }
}
#endif
