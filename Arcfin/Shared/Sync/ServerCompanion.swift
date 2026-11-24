// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import os
import AuthCore
import JellyfinAPI
import Telemetry

/// What the Arcfin Sync plugin keeps for the profile in use beyond settings: Seerr and TMDB
/// through the server, titles hidden from Continue Watching and Next Up, watch time, and the
/// admin's signed commands (clear a PIN, lock or unlock a profile). Refreshed with each sync.
@MainActor @Observable
final class ServerCompanion {
    static let shared = ServerCompanion()

    private(set) var features: Set<String> = []
    private(set) var integrations = ServerIntegrations()
    private(set) var hidden = HiddenLists()
    private(set) var watchTime: WatchTimeStatus?
    @ObservationIgnored private var watchTimeLoop: Task<Void, Never>?
    /// The server showed a signing key the pinned one didn't sign, so its commands are ignored
    /// until someone compares its fingerprint and trusts it in Settings.
    private(set) var changedKey: ServerSigningKey?
    var keyChanged: Bool { changedKey != nil }
    /// The admin replaced the key completely and this device moved to the new one over HTTPS; said once in Settings.
    var keyWasReplaced = false
    /// Profiles on this device the server's admin has locked.
    private(set) var lockedProfiles: Set<UUID> = AdminLock.lockedProfiles()

    private let client = ArcfinCompanionClient()
    private static let log = Telemetry.logger(category: "ServerCompanion")

    /// What the server's plugin offers, from this sync or, until it's done, the last one: Home
    /// loads before the sync finishes.
    func has(_ feature: String) -> Bool {
        if !features.isEmpty { return features.contains(feature) }
        guard let server = AppServices.authManager.state.credential?.baseURL else { return false }
        return (UserDefaults.standard.stringArray(forKey: Self.featuresKey(server)) ?? []).contains(feature)
    }

    private static func featuresKey(_ server: URL) -> String { "arcfin.serverFeatures.\(AdminLock.serverKey(server))" }

    /// A server that no longer has the plugin.
    func forgetFeatures(server: URL) {
        UserDefaults.standard.removeObject(forKey: Self.featuresKey(server))
        reset()
    }

    func isLocked(_ profile: UUID?) -> Bool { profile.map(lockedProfiles.contains) ?? false }

    /// The admin locked the profile in use, or its watch time is up: the app shows why instead
    /// of its screens, as it does outside the profile's access schedule.
    func blocksActiveProfile(at now: Date = TrustedClock.now) -> Bool {
        block(at: now) != nil
    }

    /// Why the profile in use can't use the app right now, if it can't.
    enum Block: Equatable {
        /// Locked by the admin; `reason` is the lock's, e.g. "pinTries" or "wipe".
        case adminLock(reason: String?)
        /// This device waits to be approved on a trusted one, which shows the same code.
        case awaitingTrust(code: String?)
        case pinRequired
        /// The profile's PIN is shorter than the admin now requires: change it to continue.
        case pinTooShort(minimum: Int)
        /// Plain HTTP away from home; `secureAddress` is the HTTPS one saved for the profile.
        case httpsRequired(secureAddress: URL?)
        case watchTime
    }

    func block(at now: Date = TrustedClock.now) -> Block? {
        _ = policyRevision
        if let credential = AppServices.authManager.state.credential {
            let id = credential.id
            if isLocked(id) {
                let reason = AdminLock.reason(profile: id)
                return reason == "trust" ? .awaitingTrust(code: trust?.code) : .adminLock(reason: reason)
            }
            if has("trustedDevices"), trust?.trusted == false { return .awaitingTrust(code: trust?.code) }
            if let policy = ServerPolicy.load(profile: id) {
                if policy.requireHttps, ServerPolicy.isInsecureAway(credential.baseURL) {
                    return .httpsRequired(secureAddress: Self.savedHTTPSAddress(for: credential))
                }
                if policy.pinRequired, pinStates[id] == false { return .pinRequired }
                if let length = pinLengths[id], length > 0, length < policy.pinMinLength { return .pinTooShort(minimum: policy.pinMinLength) }
            }
        }
        return allowsWatching(at: now) ? nil : .watchTime
    }

    /// A profile switch or a server without the plugin: nothing of the last one carries over,
    /// except admin locks, which belong to the profiles they were sent for.
    func reset() {
        features = []
        integrations = ServerIntegrations()
        hidden = HiddenLists()
        watchTime = nil
        watchTimeLoop?.cancel()
        watchTimeLoop = nil
        changedKey = nil
        unverifiedKey = nil
        trust = nil
        trustLoop?.cancel()
        trustLoop = nil
        trustRequest = nil
        sharedAccount = nil
        downloadAllowance = nil
        notices = nil
    }

    func refresh(status: ArcfinSyncStatus, credential: ServerCredential, authManager: AuthManager) async {
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let before = integrations
        // What's turned on for everyone; admin screens look at what the plugin can do instead.
        let on = status.features.filter(status.isOn)
        features = Set(on)
        UserDefaults.standard.set(on, forKey: Self.featuresKey(credential.baseURL))
        if has("integrations") {
            integrations = (try? await client.integrations(credential: credential, authHeader: header)) ?? ServerIntegrations()
        } else {
            integrations = ServerIntegrations()
        }
        forgetDeviceKeys(credential: credential, authManager: authManager)
        if integrations != before {
            AppServices.seerrRepo.reloadTMDB()
            AppRootModel.reconnectSeerr()
        }
        if has("hidden"), let lists = try? await client.hidden(credential: credential, authHeader: header) {
            hidden = lists
            AppServices.mediaRepo.applyHidden()
        }
        if has("limits") { await refreshWatchTime(credential: credential, header: header) }
        await refreshPINState(authManager: authManager)
        if has("signedCommands") { await applyCommands(server: credential, authManager: authManager) }
        updateTrustLoop(authManager: authManager)
        await refreshTrustRequests(authManager: authManager)
        await refreshHousehold(credential: credential, header: header)
    }

    /// With the server holding a key, the one on this device is never used again, so it isn't
    /// kept: a TMDB key, or a saved Seerr password.
    private func forgetDeviceKeys(credential: ServerCredential, authManager: AuthManager) {
        if integrations.tmdb, TMDBCredential.load() != nil || TMDBCredential.load(profile: credential.id) != nil {
            try? TMDBCredential.save("")
            try? TMDBCredential.save("", profile: credential.id)
            Self.log.notice("The server holds the TMDB key; removed the one saved on this device")
        }
        if integrations.seerr, !authManager.seerrPassword.isEmpty {
            authManager.removeSeerrPassword()
            Self.log.notice("The server holds the Seerr key; removed the Seerr password saved on this device")
        }
    }

    // MARK: Hidden

    func isHidden(_ itemID: String, from row: HiddenRow) -> Bool {
        let id = ArcfinCompanionClient.normalized(itemID)
        return row == .nextUp ? hidden.nextUpIDs.contains(id) : hidden.continueWatchingIDs.contains(id)
    }

    /// Hides a title on every device the person uses; it comes back to Continue Watching once
    /// it's played again.
    func setHidden(_ hide: Bool, itemID: String, from row: HiddenRow, authManager: AuthManager) async -> Bool {
        guard case .authenticated(let credential) = authManager.state else { return false }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        do {
            hidden = hide
                ? try await client.hide(itemID, from: row, credential: credential, authHeader: header)
                : try await client.unhide(itemID, from: row, credential: credential, authHeader: header)
            if hide {
                AppServices.mediaRepo.applyHidden()
            } else {
                await AppServices.mediaRepo.refreshWatchState(credential: credential, authClient: authManager.authClient)
            }
            return true
        } catch {
            Self.log.error("Couldn't \(hide ? "hide" : "unhide", privacy: .public) \(itemID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Watch time

    /// Whether the profile may watch now, by the server's last answer: not until bedtime or
    /// the day is over once it said no. Time is only counted while something plays, so the
    /// minutes left aren't counted down here; the loop below asks again while watching.
    func allowsWatching(at now: Date = TrustedClock.now) -> Bool {
        guard let watchTime, watchTime.hasLimits, !watchTime.allowed else { return true }
        return watchTime.until.map { now >= $0 } ?? false
    }

    func refreshWatchTime(authManager: AuthManager) async {
        guard has("limits"), case .authenticated(let credential) = authManager.state else { return }
        await refreshWatchTime(credential: credential, header: authManager.authClient.authHeader(token: credential.accessToken))
    }

    private func refreshWatchTime(credential: ServerCredential, header: String) async {
        guard let status = try? await client.watchTime(credential: credential, authHeader: header) else { return }
        watchTime = status
        if status.hasLimits { startWatchTimeLoop() }
    }

    /// Asks again every minute while something plays and every five otherwise, so the app
    /// closes up soon after the server stops playback, and opens again when time comes back.
    private func startWatchTimeLoop() {
        guard watchTimeLoop == nil else { return }
        watchTimeLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(PlayerActivity.shared.isPlayerOpen ? 60 : 300))
                guard let self, !Task.isCancelled, self.watchTime?.hasLimits == true else { break }
                await self.refreshWatchTime(authManager: AppServices.authManager)
            }
            self?.watchTimeLoop = nil
        }
    }

    // MARK: Signed commands

    private static let unverified = "unverified"

    /// The server's HTTPS address this profile has saved in the app (the one for away from home),
    /// if any: an address the person gave, not one the network said.
    private static func savedHTTPSAddress(for profile: ServerCredential) -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: "serverRemoteURL.\(profile.id.uuidString)"),
              let url = URL(string: raw), url.scheme?.lowercased() == "https",
              AdminLock.serverKey(url) != AdminLock.serverKey(profile.baseURL)
        else { return nil }
        return url
    }

    /// Fetches the key again from the saved HTTPS address, where the system checks the server's
    /// certificate; the same key there means the one that came over HTTP is genuine.
    private func matchesOverHTTPS(_ key: ServerSigningKey, credential: ServerCredential, header: String) async -> Bool {
        guard let https = Self.savedHTTPSAddress(for: credential) else { return false }
        var secure = credential
        secure.baseURL = https
        guard let checked = try? await client.signingKey(credential: secure, authHeader: header) else { return false }
        let matches = checked.publicKey == key.publicKey
        Self.log.notice("Checked the server's key over HTTPS: \(matches ? "it matches" : "it doesn't match", privacy: .public)")
        return matches
    }

    /// The fingerprint of the key this device trusts for the server in use, to compare on another device.
    func trustedFingerprint(for server: URL) -> String? {
        AdminLock.pinned(server: server).flatMap(ServerCommandVerifier.fingerprint)
    }

    /// Someone said the key didn't match what they compared it with: tell the server, and keep not trusting it.
    func reportMismatch(authManager: AuthManager) async {
        guard let key = changedKey ?? unverifiedKey, case .authenticated(let credential) = authManager.state else { return }
        try? await client.reportMismatch(fingerprint: Self.fingerprint(key),
                                         credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken))
        Self.log.error("Someone reported the server's key doesn't match: \(Self.fingerprint(key), privacy: .public)")
    }

    /// Tells the server which key this device trusts, if any, and which Arcfin it is: a device
    /// that has checked in is one that can follow key changes and carry out locks.
    private func checkIn(fingerprint: String, credential: ServerCredential, header: String) async {
        let info = Bundle.main.infoDictionary
        if let state = try? await client.checkIn(fingerprint: fingerprint,
                                                 appVersion: info?["CFBundleShortVersionString"] as? String ?? "",
                                                 build: info?["CFBundleVersion"] as? String ?? "",
                                                 credential: credential, authHeader: header) {
            trust = state
        }
    }

    /// Whether the server trusts this device; while it waits for approval, the code to check on a trusted one.
    private(set) var trust: TrustState?

    /// A first key seen over plain HTTP, waiting for its fingerprint to be compared.
    private(set) var unverifiedKey: ServerSigningKey?

    /// The first key is trusted by itself only over HTTPS, where the system has checked the
    /// server's certificate (Arcfin never accepts one the system doesn't). Over plain HTTP the
    /// key could have come from anyone on the network, so it waits for its fingerprint.
    static func isVerifiedByTLS(_ url: URL) -> Bool { url.scheme?.lowercased() == "https" }

    /// The fingerprint, worked out here from the key itself, so a server can't show one key's
    /// fingerprint with another key.
    static func fingerprint(_ key: ServerSigningKey) -> String {
        ServerCommandVerifier.fingerprint(key.publicKey) ?? "?"
    }

    /// Someone compared the fingerprint with the server's dashboard and it matched.
    func confirmUnverifiedKey(authManager: AuthManager) async {
        guard let key = unverifiedKey, case .authenticated(let credential) = authManager.state else { return }
        AdminLock.pin(key.publicKey, server: credential.baseURL)
        unverifiedKey = nil
        await applyCommands(server: credential, authManager: authManager)
    }

    /// Trusts the key the server shows now, after it changed without the old key's signature.
    func trustNewKey(authManager: AuthManager) async {
        guard let key = changedKey, case .authenticated(let credential) = authManager.state else { return }
        AdminLock.pin(key.publicKey, server: credential.baseURL)
        changedKey = nil
        await applyCommands(server: credential, authManager: authManager)
    }

    /// The server's commands for every profile on this device that uses it, each with its own
    /// sign-in, so a lock reaches a profile before anyone opens it.
    private func applyCommands(server credential: ServerCredential, authManager: AuthManager) async {
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let pinned = AdminLock.pinned(server: credential.baseURL)
        let holding = pinned.flatMap(ServerCommandVerifier.fingerprint)
        guard let key = try? await client.signingKey(holding: holding, credential: credential, authHeader: header) else { return }
        let decision = ServerCommandVerifier.decide(key, pinned: pinned)
        let overTLS = Self.isVerifiedByTLS(credential.baseURL)
        // Over plain HTTP, a key nothing vouches for (the first, or a complete replacement) can
        // still be trusted: the admin allows it, or the same key came from this server's HTTPS
        // address saved in the app, where the certificate was checked.
        var trustedAnyway = false
        if !overTLS, pinned == nil || decision == .changed {
            trustedAnyway = key.trustOverHttp == true
            if !trustedAnyway { trustedAnyway = await matchesOverHTTPS(key, credential: credential, header: header) }
        }
        switch decision {
        case .pin(let publicKey) where pinned == nil && !overTLS && trustedAnyway:
            AdminLock.pin(publicKey, server: credential.baseURL)
            unverifiedKey = nil
            changedKey = nil
        case .pin where pinned == nil && !overTLS:
            // First sight over plain HTTP: anyone on the network could have answered. The key
            // waits until someone compares its fingerprint with the server's dashboard.
            unverifiedKey = key
            changedKey = nil
            Self.log.notice("The server's signing key waits for its fingerprint to be checked: \(key.fingerprint, privacy: .public)")
            await checkIn(fingerprint: Self.unverified, credential: credential, header: header)
            return
        case .pin(let publicKey):
            AdminLock.pin(publicKey, server: credential.baseURL)
            unverifiedKey = nil
            changedKey = nil
        case .same:
            changedKey = nil
        case .changed where (overTLS && key.resetAt != nil) || trustedAnyway:
            // The admin replaced the key completely. Over HTTPS the system has checked the
            // server's certificate, so the new key is trusted as a first key would be.
            AdminLock.pin(key.publicKey, server: credential.baseURL)
            changedKey = nil
            keyWasReplaced = true
            Self.log.notice("The server's signing key was replaced; trusting the new one (\(overTLS ? "over HTTPS" : "checked or allowed by the admin", privacy: .public)): \(key.fingerprint, privacy: .public)")
        case .changed:
            changedKey = key
            Self.log.error("The server's signing key changed without the old key's signature; ignoring its commands")
            await checkIn(fingerprint: pinned.flatMap(ServerCommandVerifier.fingerprint) ?? Self.unverified, credential: credential, header: header)
            return
        }
        guard let pinned = AdminLock.pinned(server: credential.baseURL) else { return }
        unverifiedKey = nil
        await checkIn(fingerprint: ServerCommandVerifier.fingerprint(pinned) ?? Self.unverified, credential: credential, header: header)
        let deviceID = authManager.authClient.currentDeviceID
        let profiles = authManager.profiles.filter { AdminLock.serverKey($0.baseURL) == AdminLock.serverKey(credential.baseURL) }
        for profile in profiles {
            let profileHeader = authManager.authClient.authHeader(token: profile.accessToken)
            guard let signed = try? await client.commands(credential: profile, authHeader: profileHeader) else { continue }
            let commands = signed.compactMap { ServerCommandVerifier.verify($0, publicKey: pinned, userID: profile.userID) }
                .filter { $0.applies(toDevice: deviceID) }
                .sorted { $0.counter < $1.counter }
            for command in commands where command.counter > AdminLock.lastCounter(profile: profile.id) {
                await apply(command, to: profile, authManager: authManager)
                // A wipe signs the profile out of this device: nothing more is kept for it.
                guard authManager.profiles.contains(where: { $0.id == profile.id }) else { break }
                AdminLock.setLastCounter(command.counter, profile: profile.id)
            }
        }
        lockedProfiles = AdminLock.lockedProfiles()
    }

    private func apply(_ command: ServerCommandVerifier.Command, to profile: ServerCredential, authManager: AuthManager) async {
        let scope: AdminLock.Scope = command.device == nil ? .profile : .device
        switch command.commandKind {
        case .resetPin:
            authManager.removePin(for: profile.id)
            PINAttempts.reset(for: profile.id)
            Self.log.notice("The server's admin cleared the PIN of profile \(profile.id.uuidString, privacy: .public)")
        case .lock:
            AdminLock.setLocked(true, profile: profile.id, scope: scope)
            AdminLock.setReason(command.data?["reason"], profile: profile.id)
            Self.log.notice("The server locked profile \(profile.id.uuidString, privacy: .public) (\(scope.rawValue, privacy: .public), \(command.data?["reason"] ?? "no reason", privacy: .public))")
        case .unlock:
            AdminLock.setLocked(false, profile: profile.id, scope: scope)
            if AdminLock.reason(profile: profile.id) == "pinTries" { PINAttempts.reset(for: profile.id) }
            if !AdminLock.lockedProfiles().contains(profile.id) { AdminLock.setReason(nil, profile: profile.id) }
            Self.log.notice("The server unlocked profile \(profile.id.uuidString, privacy: .public) (\(scope.rawValue, privacy: .public))")
        case .wipe:
            await wipe(profile, isDeviceCommand: command.device != nil, authManager: authManager)
        case .policy:
            guard let data = command.data else { break }
            ServerPolicy.save(ServerPolicy(data: data), profile: profile.id)
            policyRevision += 1
            Self.log.notice("The server's security policy for profile \(profile.id.uuidString, privacy: .public): \(data.description, privacy: .public)")
        case nil:
            break
        }
    }

    // MARK: Wipe

    /// From a verified command for this device only: the profile's downloads go, the server hears
    /// it's done, and the profile is signed out here. The server keeps the device locked.
    private func wipe(_ profile: ServerCredential, isDeviceCommand: Bool, authManager: AuthManager) async {
        guard isDeviceCommand else {
            Self.log.error("Ignored a wipe that wasn't for this device alone")
            return
        }
        Self.log.notice("The server's admin wiped profile \(profile.id.uuidString, privacy: .public) from this device")
        AppServices.downloadManager.deleteAllDownloads(of: profile)
        do {
            try await client.reportWiped(credential: profile, authHeader: authManager.authClient.authHeader(token: profile.accessToken))
        } catch {
            Self.log.error("Couldn't tell the server the wipe is done: \(error.localizedDescription, privacy: .public)")
        }
        authManager.removeProfile(id: profile.id)
    }

    // MARK: Security policy

    /// Bumped when a policy arrives, so screens reading `block()` look again.
    private var policyRevision = 0

    /// Whether each profile here has a PIN, for a policy that requires one.
    private(set) var pinStates: [UUID: Bool] = [:]

    /// How many digits each profile's PIN has here (0 for none), to hold an old PIN to a longer minimum.
    private(set) var pinLengths: [UUID: Int] = [:]

    func refreshPINState(authManager: AuthManager) async {
        guard let id = authManager.state.credential?.id else { return }
        let stored = await authManager.storedPIN(for: id)
        pinStates[id] = stored != .none
        if case .set(let pin) = stored { pinLengths[id] = pin.count } else { pinLengths[id] = 0 }
    }

    func notePIN(_ hasPIN: Bool, profile: UUID) {
        pinStates[profile] = hasPIN
    }

    /// Too many wrong PINs under the admin's rules: the profile locks on this device until an
    /// admin unlocks it. True when it did.
    func pinFailed(profile: UUID, failures: Int, authManager: AuthManager) -> Bool {
        guard let maxTries = ServerPolicy.load(profile: profile)?.pinMaxTries, failures >= maxTries else { return false }
        AdminLock.setLocked(true, profile: profile, scope: .device)
        AdminLock.setReason("pinTries", profile: profile)
        lockedProfiles = AdminLock.lockedProfiles()
        Self.log.notice("Locked profile \(profile.uuidString, privacy: .public) after \(failures, privacy: .public) wrong PINs")
        if let credential = authManager.profiles.first(where: { $0.id == profile }) {
            let header = authManager.authClient.authHeader(token: credential.accessToken)
            Task { [client] in try? await client.reportPinLockout(credential: credential, authHeader: header) }
        }
        return true
    }

    func isLockedForPINTries(_ profile: UUID) -> Bool {
        isLocked(profile) && AdminLock.reason(profile: profile) == "pinTries"
    }

    // MARK: Trusted devices

    @ObservationIgnored private var trustLoop: Task<Void, Never>?

    private var isWaitingForTrust: Bool {
        guard let id = AppServices.authManager.state.credential?.id else { return false }
        if isLocked(id), AdminLock.reason(profile: id) == "trust" { return true }
        return has("trustedDevices") && trust?.trusted == false
    }

    /// While this device waits for approval, checks in every 30 seconds, so it opens as soon as
    /// a trusted device approves it.
    private func updateTrustLoop(authManager: AuthManager) {
        guard isWaitingForTrust else {
            trustLoop?.cancel()
            trustLoop = nil
            return
        }
        guard trustLoop == nil else { return }
        trustLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled, self.isWaitingForTrust,
                      case .authenticated(let credential) = authManager.state else { break }
                await self.applyCommands(server: credential, authManager: authManager)
            }
            self?.trustLoop = nil
        }
    }

    /// Another device of this person's waiting to be trusted, asked about on a trusted one.
    private(set) var trustRequest: TrustRequest?

    func refreshTrustRequests(authManager: AuthManager) async {
        guard has("trustedDevices"), trust?.trusted == true, case .authenticated(let credential) = authManager.state,
              let requests = try? await client.trustRequests(credential: credential,
                                                             authHeader: authManager.authClient.authHeader(token: credential.accessToken))
        else { return }
        trustRequest = requests.first
    }

    func answerTrust(_ trusted: Bool, authManager: AuthManager) async {
        guard let request = trustRequest, case .authenticated(let credential) = authManager.state else { return }
        trustRequest = nil
        do {
            try await client.answerTrust(trusted, requestID: request.id, credential: credential,
                                         authHeader: authManager.authClient.authHeader(token: credential.accessToken))
            Self.log.notice("\(trusted ? "Trusted" : "Didn't trust", privacy: .public) \(request.deviceName, privacy: .public)")
            HapticManager.success()
        } catch {
            HapticManager.error()
            Self.log.error("Couldn't answer the trust request: \(error.localizedDescription, privacy: .public)")
        }
        await refreshTrustRequests(authManager: authManager)
    }

    // MARK: Household

    private(set) var sharedAccount: SharedAccountInfo?
    /// Shown as the player opens on a shared account: who's watching.
    var askWhoIsWatching = false
    private(set) var downloadAllowance: DownloadAllowance?
    private(set) var notices: CachedNotices?

    private func refreshHousehold(credential: ServerCredential, header: String) async {
        sharedAccount = has("sharedAccounts") ? try? await client.sharedAccount(credential: credential, authHeader: header) : nil
        // This device's totals with each sync, so downloads made before the limits (or while
        // the server was away) count too; the answer is the allowance across all devices.
        if has("downloadLimits") {
            downloadAllowance = try? await client.reportDownloads(AppServices.downloadManager.ownTitles(), songs: MusicDownloads.shared.ownSongs(),
                                                                  credential: credential, authHeader: header)
        } else {
            downloadAllowance = nil
        }
        if has("announcements") || has("maintenance") {
            if let fetched = try? await client.notices(credential: credential, authHeader: header) {
                let cached = CachedNotices(announcements: has("announcements") ? fetched.announcements : [],
                                           maintenance: has("maintenance") ? fetched.maintenance : [])
                notices = cached
                cached.save(server: credential.baseURL)
            }
        } else {
            notices = nil
            CachedNotices.forget(server: credential.baseURL)
        }
    }

    /// The last notices fetched for the server in use, kept for when it can't be reached.
    func currentNotices() -> CachedNotices? {
        if let notices { return notices }
        guard let server = AppServices.authManager.state.credential?.baseURL else { return nil }
        return CachedNotices.load(server: server)
    }

    // MARK: Shared accounts

    private static func askedKey(_ profile: UUID) -> String { "arcfin.whoIsWatchingAsked.\(profile.uuidString)" }

    /// A shared account asks who's watching as the player opens, at most every 12 hours.
    func playerOpened() {
        guard has("sharedAccounts"), let shared = sharedAccount, shared.isShared, !shared.members.isEmpty,
              let id = AppServices.authManager.state.credential?.id else { return }
        let last = UserDefaults.standard.double(forKey: Self.askedKey(id))
        guard Date.now.timeIntervalSince1970 - last > 12 * 3600 else { return }
        askWhoIsWatching = true
    }

    /// Nobody picked copies nothing.
    func setWatching(_ memberIDs: [String], authManager: AuthManager) async {
        guard case .authenticated(let credential) = authManager.state else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.askedKey(credential.id))
        do {
            sharedAccount = try await client.setWatching(memberIDs, credential: credential,
                                                         authHeader: authManager.authClient.authHeader(token: credential.accessToken))
        } catch {
            Self.log.error("Couldn't say who's watching: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Download caps

    /// The server's reason not to start a download of about `bytes`, under the admin's caps.
    /// Nil when it fits, or when the server can't be asked.
    func downloadRefusal(itemID: String, bytes: Int64, credential: ServerCredential, authHeader: String) async -> String? {
        guard has("downloadLimits"),
              let check = try? await client.checkDownload(itemID: itemID, bytes: bytes, credential: credential, authHeader: authHeader),
              !check.allowed else { return nil }
        return check.message ?? String(localized: "This download would go over the limits your server's admin set.")
    }

    /// The server's reason not to download these songs under the admin's music caps. Nil when
    /// they fit (or there's no cap), or when the server can't be asked.
    func musicDownloadRefusal(_ songs: [DownloadedSong]) async -> String? {
        guard has("downloadLimits"), case .authenticated(let credential) = AppServices.authManager.state,
              let check = try? await client.checkMusicDownload(songs, credential: credential,
                                                               authHeader: AppServices.authManager.authClient.authHeader(token: credential.accessToken)),
              !check.allowed else { return nil }
        return check.message ?? String(localized: "This download would go over the music limits your server's admin set.")
    }

    @ObservationIgnored private var downloadReport: Task<Void, Never>?

    /// This profile's downloads on this device, after one finishes or goes. Several changes in a
    /// row are sent once.
    func reportDownloads() {
        guard has("downloadLimits") else { return }
        downloadReport?.cancel()
        downloadReport = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, case .authenticated(let credential) = AppServices.authManager.state else { return }
            let titles = AppServices.downloadManager.ownTitles()
            let header = AppServices.authManager.authClient.authHeader(token: credential.accessToken)
            if let allowance = try? await self.client.reportDownloads(titles, songs: MusicDownloads.shared.ownSongs(),
                                                                       credential: credential, authHeader: header) {
                self.downloadAllowance = allowance
            }
        }
    }
}

/// The pinned signing key per server, the last command seen per profile, and which profiles
/// the admin locked. Kept on this device, so a lock holds offline too.
enum AdminLock {

    static func serverKey(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.query = nil
        parts?.fragment = nil
        return (parts?.url?.absoluteString ?? url.absoluteString).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func pinned(server: URL) -> String? {
        UserDefaults.standard.string(forKey: "arcfin.serverSigningKey.\(serverKey(server))")
    }

    static func pin(_ publicKey: String, server: URL) {
        UserDefaults.standard.set(publicKey, forKey: "arcfin.serverSigningKey.\(serverKey(server))")
    }

    static func lastCounter(profile: UUID) -> Int64 {
        Int64(UserDefaults.standard.integer(forKey: "arcfin.serverCommandCounter.\(profile.uuidString)"))
    }

    static func setLastCounter(_ counter: Int64, profile: UUID) {
        UserDefaults.standard.set(Int(counter), forKey: "arcfin.serverCommandCounter.\(profile.uuidString)")
    }

    /// A lock for the user on all their devices, or for this one device (from the rule for
    /// devices that fall behind). Each is lifted only by its own unlock.
    enum Scope: String {
        case profile, device

        var key: String { self == .profile ? "arcfin.adminLockedProfiles" : "arcfin.adminLockedDevices" }
    }

    static func lockedProfiles() -> Set<UUID> {
        locked(.profile).union(locked(.device))
    }

    private static func locked(_ scope: Scope) -> Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: scope.key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    static func setLocked(_ isLocked: Bool, profile: UUID, scope: Scope) {
        var all = locked(scope)
        if isLocked { all.insert(profile) } else { all.remove(profile) }
        UserDefaults.standard.set(all.map(\.uuidString).sorted(), forKey: scope.key)
    }

    /// Why the admin locked the profile, when the lock said: "trust", "wipe" or "pinTries".
    static func reason(profile: UUID) -> String? {
        UserDefaults.standard.string(forKey: "arcfin.adminLockReason.\(profile.uuidString)")
    }

    static func setReason(_ reason: String?, profile: UUID) {
        UserDefaults.standard.set(reason, forKey: "arcfin.adminLockReason.\(profile.uuidString)")
    }

    /// A profile removed from this device takes its lock and counter with it.
    static func forget(profile: UUID) {
        setReason(nil, profile: profile)
        ServerPolicy.forget(profile: profile)
        PINLength.forget(profile: profile)
        setLocked(false, profile: profile, scope: .profile)
        setLocked(false, profile: profile, scope: .device)
        UserDefaults.standard.removeObject(forKey: "arcfin.serverCommandCounter.\(profile.uuidString)")
    }
}
