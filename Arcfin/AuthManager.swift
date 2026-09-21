// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import AuthCore
import JellyfinAPI
#if os(iOS)
import NetworkExtension
import CoreLocation
import Network
#endif

private final class TimeoutResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Value, Never>

    init(continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Value) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        continuation.resume(returning: value)
    }
}

@Observable
@MainActor
final class AuthManager {

    var state: AuthState = .unauthenticated
    var isChecking: Bool = true
    var profiles: [ServerCredential] = []
    /// Not persisted — re-checked once per sign-in/cold launch (see checkStoredAuth/save).
    /// Gates the Active Sessions settings screen.
    var isAdmin: Bool = false

    let authClient = JellyfinAuthClient()
    private let keychain = KeychainStore()

    // MARK: - Startup

    func checkStoredAuth() async {
        defer { isChecking = false }
        let all = await Self.withTimeout(seconds: 5, fallback: [ServerCredential]()) {
            await self.backgroundKeychainRead()
        }
        profiles = all
        guard !all.isEmpty else { return }
        let storedID = UserDefaults.standard.string(forKey: "arcfin.activeProfileID")
            .flatMap { UUID(uuidString: $0) }
        let candidate = all.first { $0.id == storedID } ?? all.first
        guard var cred = candidate else { return }

        let resolvedURL = await Self.resolveBaseURL(for: cred.baseURL, profileID: cred.id)
        if resolvedURL != cred.baseURL {
            cred.baseURL = resolvedURL
            upsert(cred)
        }

        let credForValidation = cred
        let isValid = await Self.withTimeout(seconds: 10, fallback: true) {
            await self.authClient.validateToken(credential: credForValidation)
        }
        guard isValid else { return }
        state = .authenticated(cred)
        persist(active: cred)

        // Backfills the avatar tag for credentials saved before it existed, and picks up
        // any server-side avatar change — cheap, and only happens once per cold launch.
        Task { [weak self] in
            guard let self,
                  let tag = await self.authClient.fetchUserImageTag(credential: cred),
                  tag != cred.userImageTag else { return }
            var updated = cred
            updated.userImageTag = tag
            self.upsert(updated)
            self.state = .authenticated(updated)
        }
        refreshIsAdmin(for: cred)
    }

    // MARK: - Live Wi-Fi switching

    #if os(iOS)
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "arcfin.pathMonitor")
    private var reresolveTask: Task<Void, Never>?
    #endif

    /// Watches for network changes (leaving/joining the home Wi-Fi, Wi-Fi↔cellular) and
    /// re-resolves Local vs Remote server URL live — previously this only happened once at
    /// launch, so switching networks mid-session required force-quitting the app.
    func startNetworkMonitoring() {
        #if os(iOS)
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.scheduleReresolve() }
        }
        monitor.start(queue: pathMonitorQueue)
        #endif
    }

    #if os(iOS)
    private func scheduleReresolve() {
        // NWPathMonitor can fire several updates in quick succession during a network
        // transition — debounce so we don't hammer the SSID lookup and server for each one.
        reresolveTask?.cancel()
        reresolveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await reresolveBaseURLIfNeeded()
        }
    }

    /// Not private — also called directly when the app returns to the foreground (see
    /// ContentView), since NWPathMonitor's callback can be suspended along with the rest of
    /// the app while backgrounded and not reliably fire again the moment it resumes. Coming
    /// back from the background (or Notification Center/PiP briefly covering the app) is
    /// exactly when the network is most likely to have actually changed underneath it.
    func reresolveBaseURLIfNeeded() async {
        guard case .authenticated(var cred) = state else { return }
        let resolved = await Self.resolveBaseURL(for: cred.baseURL, profileID: cred.id)
        guard resolved != cred.baseURL else { return }
        cred.baseURL = resolved
        upsert(cred)
        state = .authenticated(cred)
        persist(active: cred)
    }
    #endif

    // MARK: - Local/Remote server URL resolution

    /// Picks the Local URL when the device is on the saved home Wi-Fi network,
    /// otherwise falls back to the Remote URL, otherwise leaves the URL unchanged.
    /// `profileID` scopes the stored Local/Remote URL + home SSID to the specific signed-in
    /// profile they were configured for — these used to live under flat, unscoped keys
    /// ("serverLocalURL" etc.), shared by every profile regardless of which server it was
    /// actually for. Switching to (or signing into) a different server still found the
    /// previous server's settings sitting there and applied them anyway, silently pointing
    /// requests at the wrong host. Keyed by profile ID rather than server host because the
    /// host itself isn't stable across calls — it flips between the local and remote address
    /// as this very function resolves it.
    static func resolveBaseURL(for original: URL, profileID: UUID) async -> URL {
        #if os(iOS)
        let defaults = UserDefaults.standard
        let idKey = profileID.uuidString
        guard let localString = defaults.string(forKey: "serverLocalURL.\(idKey)"), !localString.isEmpty,
              let localURL = URL(string: localString),
              let savedSSID = defaults.string(forKey: "serverHomeSSID.\(idKey)"), !savedSSID.isEmpty
        else { return original }

        // No early-return when `original` already equals the Local URL — that used to skip
        // the SSID check entirely once resolved to local, which meant leaving the home
        // network while already on the Local URL never re-checked anything and just stayed
        // on Local forever (turning Wi-Fi off never switched to Remote). Every call now
        // always re-checks the current network against the saved home SSID.
        let currentSSID = await currentWiFiSSID()
        if currentSSID == savedSSID { return localURL }

        if let remoteString = defaults.string(forKey: "serverRemoteURL.\(idKey)"), !remoteString.isEmpty,
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
        let authorizationStatus = CLLocationManager().authorizationStatus
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            guard authorizationStatus == .notDetermined,
                  await LocationAuthWaiter().wait() else { return nil }
            return await currentWiFiSSID()
        }
        // Undocumented but widely-reported: NEHotspotNetwork.fetchCurrent silently
        // fails ("invalid result code 1") without Location authorization too, despite
        // Apple's docs saying the Access Wi-Fi Information capability alone suffices.
        //
        // Both awaits below only resolve via a callback the system controls (the user
        // answering the location permission prompt; NEHotspotNetwork's own completion) —
        // neither is guaranteed to fire in a bounded time (a prompt that fails to present,
        // or is dismissed without a decision some other way, leaves the continuation
        // dangling forever). This whole call sits directly in checkStoredAuth()'s path,
        // which the splash screen blocks on — an unbounded hang here was a silent "stuck
        // at splash" bug. Both now race against a timeout instead.
        return await withTimeout(seconds: 3, fallback: nil) {
            await withCheckedContinuation { continuation in
                NEHotspotNetwork.fetchCurrent { network in
                    continuation.resume(returning: network?.ssid)
                }
            }
        }
        #else
        nil
        #endif
    }

    /// Races `operation` against a timeout, returning `fallback` if the timeout wins. Used
    /// for the two system callbacks above that have no guaranteed completion time of their
    /// own — without this, a callback that never fires hangs checkStoredAuth() forever.
    private static func withTimeout<T: Sendable>(seconds: Double, fallback: T, operation: @escaping @Sendable () async -> T) async -> T {
        await withCheckedContinuation { continuation in
            let result = TimeoutResult(continuation: continuation)
            Task {
                result.finish(await operation())
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                result.finish(fallback)
            }
        }
    }

    // MARK: - Save & activate (initial sign-in)

    func save(_ credential: ServerCredential) {
        upsert(credential)
        persist(active: credential)
        state = .authenticated(credential)
        refreshIsAdmin(for: credential)
    }

    // MARK: - Multi-profile management

    func addProfile(_ credential: ServerCredential) {
        upsert(credential)
        persist(active: credential)
        state = .authenticated(credential)
        refreshIsAdmin(for: credential)
    }

    func switchTo(_ credential: ServerCredential) {
        persist(active: credential)
        state = .authenticated(credential)
        refreshIsAdmin(for: credential)
    }

    /// isAdmin isn't persisted per profile — every place that makes a credential the
    /// active one re-checks it fresh so switching profiles can't show a stale value from
    /// whichever profile was active before.
    private func refreshIsAdmin(for credential: ServerCredential) {
        isAdmin = false
        Task { [weak self] in
            guard let self else { return }
            self.isAdmin = await self.authClient.fetchIsAdministrator(credential: credential)
        }
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
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    func wait() async -> Bool {
        guard manager.authorizationStatus == .notDetermined else {
            return manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.finish(false)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let granted = manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        finish(granted)
    }

    private func finish(_ granted: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: granted)
    }
}
#endif
