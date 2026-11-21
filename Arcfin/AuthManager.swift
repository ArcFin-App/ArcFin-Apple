// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import AuthCore
import ImageCache
import JellyfinAPI
import SyncEngine
import Telemetry
import os
import Security
#if os(iOS)
import NetworkExtension
import CoreLocation
import Network
#endif
#if os(iOS) || os(tvOS)
import UIKit
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

    var state: AuthState = .unauthenticated {
        didSet {
            if let id = state.credential?.id, id != oldValue.credential?.id {
                ProfileSettings.activate(profile: id.uuidString, profiles: profiles.map(\.id.uuidString))
                activateSeerrAccount(for: id)
                if oldValue.credential != nil { forgetPreviousProfile() }
            }
        }
    }
    var isChecking: Bool = true
    var profiles: [ServerCredential] = []
    /// Not persisted — re-checked once per sign-in/cold launch (see checkStoredAuth/save).
    /// Gates the Active Sessions settings screen.
    var isAdmin: Bool = false
    /// The profile whose sign-in the server stopped accepting (password changed, device
    /// removed). The sign-in screen opens on its server and says why.
    var expiredCredential: ServerCredential?
    /// Sign-outs that left another profile in use, so each window can show the profile picker.
    private(set) var signOutsToNextProfile = 0
    @ObservationIgnored private var lastSignInCheck: Date?

    /// nil until the first check completes, or if the server has no Arcfin Sync plugin or
    /// isn't reachable, see ArcfinSyncClient.fetchStatus.
    var arcfinSyncStatus: ArcfinSyncStatus?
    /// Keys the admin has locked server-side, as the server last said for the active profile.
    /// Kept through a sync, a failed one and launches offline; empty when the server has never
    /// had the plugin.
    var arcfinSyncLockedKeys: Set<String> = []
    /// nil until a sync actually completes. Distinct from arcfinSyncStatus being non-nil,
    /// which only means the plugin was detected — this is what a "Last synced" label reads.
    var arcfinSyncLastSyncedAt: Date?
    var isSyncingArcfin: Bool = false

    /// Keychain-backed (not UserDefaults/@AppStorage like the rest of the Seerr fields —
    /// this one is a secret). Loaded once in checkStoredAuth(); every read/write site in the
    /// app goes through this observable property instead of its own Keychain round-trip, so
    /// all of them stay in sync the same way @AppStorage used to keep them in sync for free.
    var seerrPassword: String = ""

    let authClient = JellyfinAuthClient()
    private let syncClient = ArcfinSyncClient()
    @ObservationIgnored private var settingsObserver: NSObjectProtocol?
    @ObservationIgnored private var settingsPushTask: Task<Void, Never>?
    private let keychain = KeychainStore()

    // MARK: - Startup

    @ObservationIgnored private var storedAuthCheck: Task<Void, Never>?

    /// The launch's stored sign-in check, run once whichever screen asks first: the window, or
    /// CarPlay when the app starts in the car.
    func checkStoredAuthOnce() async {
        if storedAuthCheck == nil { storedAuthCheck = Task { await checkStoredAuth() } }
        await storedAuthCheck?.value
    }

    func checkStoredAuth() async {
        defer { isChecking = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ArcfinScreenshotDemo") {
            await signInToDemoServerForScreenshots()
            return
        }
        #endif
        // A locked device (a CarPlay, Lock Screen, Siri or background launch, for sign-ins
        // saved before they moved to after-first-unlock) isn't "no profiles": the check waits
        // for the unlock and reads again, so the launch, and the PIN lock after it, see the
        // real profiles. Any other failure counts as none, as before.
        var read = await readStoredServers()
        var waits = 0
        while case .locked = read, waits < 3, await Self.protectedDataAvailable() {
            waits += 1
            read = await readStoredServers()
        }
        let all: [ServerCredential]
        if case .servers(let servers) = read {
            all = servers
            upgradeKeychainAccessibilityOnce()
        } else {
            all = []
        }
        seerrPassword = await keychainRead { (try? $0.loadSeerrPassword()) ?? "" }
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
        guard isValid else {
            expiredCredential = cred
            return
        }
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
            // Another profile may have been picked while this ran; it stays.
            if self.state.credential?.id == cred.id { self.state = .authenticated(updated) }
        }
        BottomNavPrefs.switchLayout(toProfile: cred.id.uuidString)
        refreshIsAdmin(for: cred)
        refreshArcfinSync(for: cred)
    }

    #if DEBUG
    /// For the screenshot UI test: Jellyfin's public demo server, so the run needs no account
    /// or secrets. Kept in memory and never falls back to stored profiles, so a run on a Mac
    /// leaves that Mac's own sign-ins alone and can't capture its library. If the demo server
    /// can't be reached the app stays on the sign-in screen and the test skips.
    private func signInToDemoServerForScreenshots() async {
        guard let url = URL(string: "https://demo.jellyfin.org/stable"),
              let credential = try? await authClient.authenticate(baseURL: url, username: "demo", password: "")
        else { return }
        profiles = [credential]
        state = .authenticated(credential)
    }
    #endif

    // MARK: - Live Wi-Fi switching

    #if os(iOS)
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "arcfin.pathMonitor")
    private var reresolveTask: Task<Void, Never>?
    #endif

    /// Watches for network changes (leaving/joining the home Wi-Fi, Wi-Fi↔cellular) and
    /// re-resolves Local vs Remote server URL live — previously this only happened once at
    /// launch, so switching networks mid-session required force-quitting the app.
    /// Bumped after each settled network change, for work that should retry once the
    /// connection is back (offline progress sync).
    private(set) var networkChanges = 0

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
            networkChanges += 1
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

    /// `asksForLocation`: when Location hasn't been asked yet, ask and wait for the answer.
    /// Only Settings does; the launch path doesn't, so it never waits on a prompt.
    static func currentWiFiSSID(asksForLocation: Bool = false) async -> String? {
        #if os(iOS)
        #if targetEnvironment(simulator)
        // NEHotspotNetwork.fetchCurrent always fails here ("invalid result code 1") — the
        // Simulator has no real Wi-Fi radio to report on, regardless of entitlement or
        // Location authorization. Skip straight to nil instead of requesting Location
        // permission and spamming nehelper every time this runs on a dev build.
        return nil
        #else
        let authorizationStatus = CLLocationManager().authorizationStatus
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            guard asksForLocation, authorizationStatus == .notDetermined,
                  await LocationAuthWaiter().wait() else { return nil }
            return await currentWiFiSSID()
        }
        // Undocumented but widely-reported: NEHotspotNetwork.fetchCurrent silently
        // fails ("invalid result code 1") without Location authorization too, despite
        // Apple's docs saying the Access Wi-Fi Information capability alone suffices.
        //
        // NEHotspotNetwork's completion isn't guaranteed to fire in a bounded time, and this
        // call sits in checkStoredAuth()'s path, which the splash screen blocks on, so it
        // races a timeout.
        return await withTimeout(seconds: 3, fallback: nil) {
            await withCheckedContinuation { continuation in
                NEHotspotNetwork.fetchCurrent { network in
                    continuation.resume(returning: network?.ssid)
                }
            }
        }
        #endif
        #else
        nil
        #endif
    }

    /// Races `operation` against a timeout, returning `fallback` if the timeout wins. Used
    /// for work with no guaranteed completion time of its own — without this, a callback
    /// that never fires hangs checkStoredAuth() forever.
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

    func save(_ newCredential: ServerCredential) {
        let credential = keepingProfileID(newCredential)
        expiredCredential = nil
        upsert(credential)
        persist(active: credential)
        state = .authenticated(credential)
        BottomNavPrefs.switchLayout(toProfile: credential.id.uuidString)
        refreshIsAdmin(for: credential)
        refreshArcfinSync(for: credential)
    }

    // MARK: - Multi-profile management

    func addProfile(_ newCredential: ServerCredential) {
        let credential = keepingProfileID(newCredential)
        upsert(credential)
        persist(active: credential)
        state = .authenticated(credential)
        BottomNavPrefs.switchLayout(toProfile: credential.id.uuidString)
        refreshIsAdmin(for: credential)
        refreshArcfinSync(for: credential)
    }

    func switchTo(_ credential: ServerCredential) {
        persist(active: credential)
        state = .authenticated(credential)
        BottomNavPrefs.switchLayout(toProfile: credential.id.uuidString)
        refreshIsAdmin(for: credential)
        refreshArcfinSync(for: credential)
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

    /// Checks for the Arcfin Sync plugin and, if present, syncs settings — called at every
    /// place a credential becomes the active one, same as refreshIsAdmin. A missing/unreachable
    /// plugin resets both fields to their "not present" defaults rather than leaving a stale
    /// status from a previously active profile.
    private static let syncLog = Telemetry.logger(category: "ArcfinSync")

    private func refreshArcfinSync(for credential: ServerCredential) {
        // A push the previous profile scheduled mustn't land in this one's record.
        settingsPushTask?.cancel()
        arcfinSyncStatus = nil
        arcfinSyncLockedKeys = SettingsSyncEngine.lockedKeys(profile: credential.id.uuidString)
        arcfinSyncLastSyncedAt = nil
        isSyncingArcfin = true
        Task { [weak self] in
            guard let self else { return }
            // A switch since has started its own sync; this one leaves that alone.
            defer { if self.isActive(credential) { self.isSyncingArcfin = false } }
            // The locks last seen stay while the server can't be reached; only a server that
            // answers without the plugin clears them.
            let presence = await self.syncClient.fetchStatus(baseURL: credential.baseURL)
            guard self.isActive(credential) else { return }
            guard case .installed(let status) = presence else {
                Self.syncLog.notice("Arcfin Sync plugin not detected at \(credential.baseURL.absoluteString, privacy: .public)")
                if presence == .notInstalled {
                    SettingsSyncEngine.forgetLockedKeys(profile: credential.id.uuidString)
                    self.arcfinSyncLockedKeys = []
                }
                return
            }
            Self.syncLog.notice("Arcfin Sync plugin detected: version \(status.version, privacy: .public)")
            self.arcfinSyncStatus = status
            let header = self.authClient.authHeader(token: credential.accessToken)
            let locked = await SettingsSyncEngine.sync(credential: credential, authHeader: header,
                                                       isCurrent: { await self.isActive(credential) })
            guard self.isActive(credential) else { return }
            if let locked {
                self.arcfinSyncLockedKeys = locked
                self.arcfinSyncLastSyncedAt = .now
            }
            self.watchSettingsChanges()
            // Which encoders the server's hardware really has (plugin 0.3+); nil leaves it to
            // the learn-on-failure path.
            if let encoders = await self.syncClient.fetchEncoders(credential: credential, authHeader: header),
               let av1 = encoders.encoders["av1"] {
                AV1Encoding.apply(serverEncodesAV1: av1, on: credential.baseURL)
                Self.syncLog.notice("Server encoders (\(encoders.hardwareAcceleration, privacy: .public)): AV1 \(av1 ? "works" : "unavailable", privacy: .public)")
            }
            Self.syncLog.notice("Sync complete — \(self.arcfinSyncLockedKeys.count, privacy: .public) locked key(s): \(self.arcfinSyncLockedKeys.sorted().joined(separator: ", "), privacy: .public)")
        }
    }

    /// Sends a synced setting changed here a moment after the change, rather than at the next
    /// launch, so other devices pick it up and the next sync doesn't see it as stale.
    private func watchSettingsChanges() {
        guard settingsObserver == nil else { return }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.scheduleSettingsPush() }
        }
    }

    private func scheduleSettingsPush() {
        // A sync's own writes land here too; it's already handling them.
        guard arcfinSyncStatus != nil, !isSyncingArcfin else { return }
        settingsPushTask?.cancel()
        settingsPushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, !self.isSyncingArcfin,
                  case .authenticated(let credential) = self.state,
                  SettingsSyncEngine.hasLocalChanges(profile: credential.id.uuidString)
            else { return }
            self.isSyncingArcfin = true
            defer { if self.isActive(credential) { self.isSyncingArcfin = false } }
            let header = self.authClient.authHeader(token: credential.accessToken)
            let locked = await SettingsSyncEngine.sync(credential: credential, authHeader: header,
                                                       isCurrent: { await self.isActive(credential) })
            guard self.isActive(credential), let locked else { return }
            self.arcfinSyncLockedKeys = locked
            self.arcfinSyncLastSyncedAt = .now
        }
    }

    private func isActive(_ credential: ServerCredential) -> Bool { state.credential?.id == credential.id }

    /// Manual re-sync for a "Sync Now" button — re-runs the exact same check/sync as every
    /// automatic call site, just triggered on demand against whichever profile is active.
    func syncArcfinNow() {
        guard case .authenticated(let credential) = state else { return }
        refreshArcfinSync(for: credential)
    }

    /// What belonged to the profile just switched away from: its playlists, its titles in
    /// Spotlight and the widgets, and what the background check had seen, so the next check
    /// only records the new profile's library instead of announcing it.
    private func forgetPreviousProfile() {
        #if !os(tvOS)
        Task { await SpotlightIndexer.clear() }
        WidgetSnapshotUpdater.clear()
        SeerrSpotlightStore.clear()
        BackgroundRefresh.resetState()
        #endif
        #if os(tvOS)
        TopShelfArtwork.clear()
        #endif
        SplashMosaicStore.clear()
        PlaylistStore.shared.clear()
    }

    func removeProfile(id: UUID) {
        if let removed = profiles.first(where: { $0.id == id }) {
            let client = authClient
            Task.detached { await client.logout(credential: removed) }
        }
        keychainWrite { try $0.delete(serverID: id) }
        keychainWrite { try $0.deletePin(for: id) }
        keychainWrite { try $0.deleteSeerrPassword(profile: id) }
        UserDefaults.standard.removeObject(forKey: Self.seerrUsernameKey(for: id))
        for key in Self.perProfileSeerrKeys { UserDefaults.standard.removeObject(forKey: Self.perProfileKey(key, for: id)) }
        try? TMDBCredential.save("", profile: id)
        MusicScrobbler.forget(profile: id)
        ProfileSettings.forget(profile: id.uuidString)
        profiles.removeAll { $0.id == id }
        if profiles.isEmpty { clearDeviceSignIns() }
        // Spotlight, the widgets, playlists and the parental rules only ever hold the profile in
        // use (a switch clears them), so removing another profile leaves them alone.
        guard case .authenticated(let current) = state, current.id == id else { return }
        ProfileRules.shared.clear()
        if let next = profiles.first {
            // Who goes next is picked on the profile picker, with their PIN if they have one.
            signOutsToNextProfile += 1
            AppServices.hasPassedLock = false
            switchTo(next)
        } else {
            forgetPreviousProfile()
            UserDefaults.standard.removeObject(forKey: "arcfin.activeProfileID")
            state = .unauthenticated
        }
    }

    /// With no profile left, the sign-ins kept for the whole device go too: Seerr (its active
    /// slot only moves when another profile takes over), the TMDB key, the gateway headers,
    /// and what was searched and watched. Downloads stay, as the sign-out prompt says.
    private func clearDeviceSignIns() {
        let defaults = UserDefaults.standard
        for key in ["seerrURL", "seerrUsername", "seerrAuthMethod", Self.seerrOwnerKey, "recentSearches"] {
            defaults.removeObject(forKey: key)
        }
        seerrPassword = ""
        keychainWrite { try $0.deleteSeerrPassword() }
        try? TMDBCredential.save("")
        CustomHTTPHeaders.removeAll()
        ShowTrackMemory.clear()
        ImageCache.clear()
    }

    /// Signing in again as someone who already has a profile replaces that profile's token
    /// instead of adding a second one, so its downloads, PIN and Seerr sign-in, all keyed by
    /// the profile's id, carry over.
    private func keepingProfileID(_ credential: ServerCredential) -> ServerCredential {
        guard let existing = profiles.first(where: {
            $0.userID == credential.userID && $0.baseURL == credential.baseURL
        }), existing.id != credential.id else { return credential }
        return ServerCredential(id: existing.id, baseURL: credential.baseURL, userID: credential.userID,
                                accessToken: credential.accessToken, displayName: credential.displayName,
                                userImageTag: credential.userImageTag ?? existing.userImageTag)
    }

    // MARK: - Expired sign-in

    /// Called when the app comes back and when Home fails to load. An unreachable server
    /// counts as still signed in, as at launch; only a rejected token signs out.
    func checkSignInStillValid() async {
        guard case .authenticated(let cred) = state else { return }
        if let last = lastSignInCheck, Date().timeIntervalSince(last) < 30 { return }
        lastSignInCheck = Date()
        let isValid = await authClient.validateToken(credential: cred)
        guard !isValid, state.credential?.id == cred.id else { return }
        expiredCredential = cred
        state = .unauthenticated
    }

    // MARK: - Sign out (removes current profile)

    func signOut() {
        if case .authenticated(let cred) = state {
            removeProfile(id: cred.id)
        }
    }

    // MARK: - PIN management

    nonisolated enum StoredPIN: Sendable, Equatable {
        case none
        case set(String)
        /// The device is locked, so the Keychain can't answer yet. Counts as a PIN that can't
        /// be checked yet, never as no PIN.
        case unreadable
    }

    enum PINCheck: Equatable {
        case correct, incorrect, unreadable
        case waiting(TimeInterval)

        var message: String? {
            switch self {
            case .correct: nil
            case .incorrect: String(localized: "Incorrect PIN")
            case .unreadable: String(localized: "Couldn't check the PIN. Try again.")
            case .waiting(let seconds):
                String(localized: "Too many tries. Try again in \(PINAttempts.formatted(seconds)).")
            }
        }

        /// What the PIN pad says as it opens: the PIN couldn't be read, or a wait is still on.
        static func message(opening stored: StoredPIN, for credentialID: UUID) -> String? {
            if stored == .unreadable { return PINCheck.unreadable.message }
            return PINAttempts.remainingWait(for: credentialID).flatMap { PINCheck.waiting($0).message }
        }
    }

    func storedPIN(for credentialID: UUID) async -> StoredPIN {
        await keychainRead { k in
            do {
                return try k.loadPin(for: credentialID).map(StoredPIN.set) ?? .none
            } catch KeychainError.unexpectedStatus(let status) where status == errSecInteractionNotAllowed {
                return .unreadable
            } catch {
                Self.logPINReadFailureOnce(error)
                return .none
            }
        }
    }

    private nonisolated static let pinReadFailureLogged = OSAllocatedUnfairLock(initialState: false)

    /// Once per launch: an app built without signing gets this on every read.
    private nonisolated static func logPINReadFailureOnce(_ error: Error) {
        guard pinReadFailureLogged.withLock({ logged in defer { logged = true }; return !logged }) else { return }
        keychainLog.error("Reading a PIN failed, so it counts as none: \(String(describing: error), privacy: .public)")
    }

    /// Checks a typed PIN against the stored one, counting wrong tries (see `PINAttempts`).
    func checkPIN(_ entered: String, for credentialID: UUID) async -> PINCheck {
        if let wait = PINAttempts.remainingWait(for: credentialID) { return .waiting(wait) }
        switch await storedPIN(for: credentialID) {
        case .unreadable:
            return .unreadable
        case .set(let pin) where pin != entered:
            PINAttempts.recordFailure(for: credentialID)
            return PINAttempts.remainingWait(for: credentialID).map(PINCheck.waiting) ?? .incorrect
        case .set, .none:
            PINAttempts.reset(for: credentialID)
            return .correct
        }
    }

    func savePin(_ pin: String, for credentialID: UUID) {
        keychainWrite { try $0.savePin(pin, for: credentialID) }
    }

    func removePin(for credentialID: UUID) {
        keychainWrite { try $0.deletePin(for: credentialID) }
    }

    // MARK: - Seerr account per profile

    /// Whose Seerr sign-in is in the active slot (the `seerrUsername` default and the
    /// Keychain password everything reads). Seerr accounts are per person: before, the slot
    /// was shared, so switching profile kept the previous person signed in to Seerr — their
    /// watchlist and requests, and new requests made in their name.
    private static let seerrOwnerKey = "arcfin.seerrAccountOwner"

    private static func seerrUsernameKey(for id: UUID) -> String { "seerrUsername.\(id.uuidString)" }
    /// Each profile's own Seerr address and sign-in method, like its username: profiles can
    /// use different Seerr servers.
    private static let perProfileSeerrKeys = ["seerrURL", "seerrAuthMethod"]
    private static func perProfileKey(_ key: String, for id: UUID) -> String { "\(key).\(id.uuidString)" }

    /// A profile's Seerr server, sign-in method and username, from the slot in use when it's
    /// the active profile's. Nil when it hasn't connected Seerr.
    func seerrConnection(for id: UUID) -> (url: String, authMethod: String, username: String)? {
        let defaults = UserDefaults.standard
        let isLive = defaults.string(forKey: Self.seerrOwnerKey) == id.uuidString
        func value(_ key: String, stored: String) -> String {
            defaults.string(forKey: isLive ? key : stored) ?? ""
        }
        let url = value("seerrURL", stored: Self.perProfileKey("seerrURL", for: id))
        guard !url.isEmpty else { return nil }
        return (url, value("seerrAuthMethod", stored: Self.perProfileKey("seerrAuthMethod", for: id)),
                value("seerrUsername", stored: Self.seerrUsernameKey(for: id)))
    }

    /// Gives a profile the Seerr connection another device sent, without a password: a
    /// Jellyfin sign-in goes through Quick Connect, a local account signs in here.
    func setSeerrConnection(url: String, authMethod: String, username: String, for id: UUID) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.seerrOwnerKey) == id.uuidString {
            // The slot in use: Seerr reconfigures from it.
            defaults.set(authMethod, forKey: "seerrAuthMethod")
            defaults.set(username, forKey: "seerrUsername")
            defaults.set(url, forKey: "seerrURL")
        } else {
            defaults.set(authMethod, forKey: Self.perProfileKey("seerrAuthMethod", for: id))
            defaults.set(username, forKey: Self.seerrUsernameKey(for: id))
            defaults.set(url, forKey: Self.perProfileKey("seerrURL", for: id))
        }
    }

    /// The Seerr sign-in that comes with signing in (the server sets Seerr to the Jellyfin
    /// account), saved under the profile it's for. It's saved before that profile becomes the
    /// active one, while the slot in use is still the previous person's; switching to it puts
    /// it in place. With no owner yet, the slot goes to whoever signs in.
    func saveSeerrSignIn(url: String, authMethod: String, username: String, password: String,
                         for credential: ServerCredential) {
        let id = keepingProfileID(credential).id
        let defaults = UserDefaults.standard
        let owner = defaults.string(forKey: Self.seerrOwnerKey)
        if owner == nil || owner == id.uuidString {
            defaults.set(authMethod, forKey: "seerrAuthMethod")
            defaults.set(username, forKey: "seerrUsername")
            defaults.set(url, forKey: "seerrURL")
            saveSeerrPassword(password)
        } else {
            defaults.set(authMethod, forKey: Self.perProfileKey("seerrAuthMethod", for: id))
            defaults.set(username, forKey: Self.seerrUsernameKey(for: id))
            defaults.set(url, forKey: Self.perProfileKey("seerrURL", for: id))
            keychainWrite { try $0.saveSeerrPassword(password, profile: id) }
        }
    }

    /// Sets the outgoing profile's Seerr sign-in aside and puts the incoming one's in place
    /// (or none, when it hasn't connected Seerr), which reconfigures Seerr through the
    /// observers on the slot.
    private func activateSeerrAccount(for id: UUID) {
        let defaults = UserDefaults.standard
        let owner = defaults.string(forKey: Self.seerrOwnerKey).flatMap(UUID.init(uuidString:))
        guard owner != id else { return }
        defaults.set(id.uuidString, forKey: Self.seerrOwnerKey)
        // First run with this: what's in the slot already belongs to the active profile.
        guard let owner else { return }

        let outgoingPassword = seerrPassword
        // A profile that was just removed has nothing to set aside.
        let stashOutgoing = profiles.contains { $0.id == owner }
        if stashOutgoing {
            defaults.set(defaults.string(forKey: "seerrUsername") ?? "", forKey: Self.seerrUsernameKey(for: owner))
            for key in Self.perProfileSeerrKeys {
                defaults.set(defaults.string(forKey: key) ?? "", forKey: Self.perProfileKey(key, for: owner))
            }
            // The TMDB key is each profile's too; swapped here, before anything reloads TMDB.
            try? TMDBCredential.save(TMDBCredential.load() ?? "", profile: owner)
        }
        defaults.set(defaults.string(forKey: Self.seerrUsernameKey(for: id)) ?? "", forKey: "seerrUsername")
        for key in Self.perProfileSeerrKeys {
            if let value = defaults.string(forKey: Self.perProfileKey(key, for: id)), !value.isEmpty {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        try? TMDBCredential.save(TMDBCredential.load(profile: id) ?? "")
        seerrPassword = ""
        let k = keychain
        // Queued now, not from a Task, so a quick second switch can't overtake it.
        Self.keychainQueue.async {
            do {
                if stashOutgoing {
                    if outgoingPassword.isEmpty { try k.deleteSeerrPassword(profile: owner) }
                    else { try k.saveSeerrPassword(outgoingPassword, profile: owner) }
                }
            } catch {
                Self.keychainLog.error("Setting the Seerr password aside failed: \(String(describing: error), privacy: .public)")
            }
            let password = (try? k.loadSeerrPassword(profile: id)) ?? ""
            do {
                if password.isEmpty { try k.deleteSeerrPassword() } else { try k.saveSeerrPassword(password) }
            } catch {
                Self.keychainLog.error("Putting the Seerr password in place failed: \(String(describing: error), privacy: .public)")
            }
            Task { @MainActor in
                // Another switch may have happened while the Keychain was read.
                guard self.state.credential?.id == id else { return }
                self.seerrPassword = password
            }
        }
    }

    // MARK: - Seerr password (Keychain — see seerrPassword's own doc comment)

    func saveSeerrPassword(_ password: String) {
        seerrPassword = password
        keychainWrite { try $0.saveSeerrPassword(password) }
    }

    func removeSeerrPassword() {
        seerrPassword = ""
        keychainWrite { try $0.deleteSeerrPassword() }
    }

    // MARK: - Stored servers (async — always off main thread)

    func fetchStoredServers() async -> [ServerCredential] {
        await backgroundKeychainRead()
    }

    // MARK: - Private

    private func upsert(_ credential: ServerCredential) {
        keychainWrite { try $0.save(credential) }
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
        await keychainRead { (try? $0.allServers()) ?? [] }
    }

    private enum StoredServersRead: Sendable {
        case servers([ServerCredential])
        /// The device is locked and the items are only readable when it isn't.
        case locked
        case failed
    }

    private func readStoredServers() async -> StoredServersRead {
        await Self.withTimeout(seconds: 5, fallback: StoredServersRead.failed) {
            await self.keychainRead { k -> StoredServersRead in
                do {
                    return .servers(try k.allServers())
                } catch KeychainError.unexpectedStatus(let status) where status == errSecInteractionNotAllowed {
                    return .locked
                } catch {
                    return .failed
                }
            }
        }
    }

    private nonisolated static let keychainUpgradedKey = "arcfin.keychainAfterFirstUnlock"

    /// Moves sign-ins saved before 0.5.0 to after-first-unlock, once. Only marked done when it
    /// worked, so a failure is tried again at the next launch.
    private func upgradeKeychainAccessibilityOnce() {
        guard !UserDefaults.standard.bool(forKey: Self.keychainUpgradedKey) else { return }
        keychainWrite { k in
            try k.upgradeAccessibility()
            UserDefaults.standard.set(true, forKey: Self.keychainUpgradedKey)
        }
    }

    /// Waits until the device is unlocked; true when it is. Nothing to wait for on the Mac.
    private static func protectedDataAvailable() async -> Bool {
        #if os(iOS) || os(tvOS)
        // Made before the check, so an unlock in between isn't missed.
        let unlocks = NotificationCenter.default.notifications(named: UIApplication.protectedDataDidBecomeAvailableNotification)
        if UIApplication.shared.isProtectedDataAvailable { return true }
        for await _ in unlocks { return true }
        return false
        #else
        return false
        #endif
    }

    // MARK: - Keychain queue

    /// Every Keychain call goes through this one serial queue, so writes land in the order
    /// they were made (two quick profile switches, or a sign-in and its avatar update, used
    /// to race) and a read sees the writes made before it.
    private nonisolated static let keychainQueue = DispatchQueue(label: "arcfin.keychain", qos: .userInitiated)
    private nonisolated static let keychainLog = Telemetry.logger(category: "Keychain")

    private func keychainWrite(_ work: @escaping @Sendable (KeychainStore) throws -> Void) {
        let k = keychain
        Self.keychainQueue.async {
            do { try work(k) } catch {
                Self.keychainLog.error("Keychain write failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func keychainRead<T: Sendable>(_ work: @escaping @Sendable (KeychainStore) -> T) async -> T {
        let k = keychain
        return await withCheckedContinuation { continuation in
            Self.keychainQueue.async { continuation.resume(returning: work(k)) }
        }
    }
}

/// Wrong PINs per profile, kept on this device across launches: after five, each further
/// try waits 30 seconds, then 1, 5 and 15 minutes. Timed on the trusted clock, so changing
/// the device's time doesn't shorten a wait; a right PIN or Face ID / Touch ID starts over.
nonisolated enum PINAttempts {
    private static let freeTries = 5
    private static let waits: [TimeInterval] = [30, 60, 5 * 60, 15 * 60]

    private static func failuresKey(_ id: UUID) -> String { "arcfin.pinFailures.\(id.uuidString)" }
    private static func waitUntilKey(_ id: UUID) -> String { "arcfin.pinWaitUntil.\(id.uuidString)" }

    static func remainingWait(for id: UUID) -> TimeInterval? {
        let until = UserDefaults.standard.double(forKey: waitUntilKey(id))
        guard until > 0 else { return nil }
        // Capped, so a clock that went back can't make a wait longer than the longest.
        let remaining = min(until - TrustedClock.now.timeIntervalSince1970, waits[waits.count - 1])
        return remaining > 0 ? remaining : nil
    }

    static func recordFailure(for id: UUID) {
        let defaults = UserDefaults.standard
        let failures = defaults.integer(forKey: failuresKey(id)) + 1
        defaults.set(failures, forKey: failuresKey(id))
        guard failures >= freeTries else { return }
        let wait = waits[min(failures - freeTries, waits.count - 1)]
        defaults.set(TrustedClock.now.timeIntervalSince1970 + wait, forKey: waitUntilKey(id))
    }

    static func reset(for id: UUID) {
        UserDefaults.standard.removeObject(forKey: failuresKey(id))
        UserDefaults.standard.removeObject(forKey: waitUntilKey(id))
    }

    static func formatted(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.up))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 1,
                              fractionalPart: .hide(rounded: .up)))
    }
}

#if os(iOS)
/// Requests When In Use location authorization if not yet determined, and waits for
/// the user's decision before returning — NEHotspotNetwork.fetchCurrent needs it granted.
/// No timeout: it's only used from Settings, where the person is reading the prompt.
@MainActor
private final class LocationAuthWaiter: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        guard manager.authorizationStatus == .notDetermined else {
            return manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // The first callback comes as soon as the delegate is set, before any answer.
        guard manager.authorizationStatus != .notDetermined else { return }
        let granted = manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        finish(granted)
    }

    private func finish(_ granted: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: granted)
    }
}
#endif
