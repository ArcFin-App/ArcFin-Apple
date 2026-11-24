// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import SwiftData
import JellyfinAPI
import SeerrAPI
import SyncEngine

/// The state under each platform's `ContentView`: the splash, the stored sign-in and PIN lock
/// checks, deep links, the tour and What's New, Seerr set-up, and the loops that run while the
/// app is active.
@MainActor
@Observable
final class AppRootModel {
    let authManager = AppServices.authManager
    let mediaRepo = AppServices.mediaRepo
    let playbackPresenter = PlaybackPresenter()
    let seerrRepo = AppServices.seerrRepo
    let downloadManager = AppServices.downloadManager
    let syncPlayManager = AppServices.syncPlayManager
    let sharePlayManager = AppServices.sharePlayManager
    let introduction = AppServices.introduction
    var splashDone = false
    var isAppLocked = false
    /// The lock came up over screens already open, which stay underneath, hidden and out of
    /// reach, so they're as they were once it opens. At launch nothing is built behind it.
    var keepsContentUnderLock = false
    /// Bumped when another profile is picked over kept screens, which then start afresh rather
    /// than show where the last one was.
    private(set) var contentGeneration = 0
    @ObservationIgnored private var lockedProfileID: UUID?
    var activeProfileHasPIN = false
    /// The stored sign-in and the PIN lock have been checked this launch.
    var launchChecked = false
    var showSeerrSetupPrompt = false
    /// Why connecting Seerr by itself didn't work, for the prompt that asks for the password.
    var seerrSetupError: String?
    @ObservationIgnored private var isConnectingSeerr = false
    @ObservationIgnored private var handledSignOuts = AppServices.authManager.signOutsToNextProfile
    /// Links that came while the lock was up or not yet decided, run once it opens.
    @ObservationIgnored private var heldLinks: [URL] = []
    // Shared by every window's model, so a second window doesn't start a second set and one
    // going to the background doesn't stop the other's.
    private static var heartbeatTask: Task<Void, Never>?
    private static var arcfinSyncTask: Task<Void, Never>?
    private static var seerrPollTask: Task<Void, Never>?
    private static var lastForegroundRefresh: Date?

    /// Routes an arcfin:// link from a widget, Live Activity, the Top Shelf or a control, and
    /// the Apple TV's Quick Connect QR code.
    func handleDeepLink(_ url: URL) {
        if QuickConnectApproval.shared.open(url) { return }
        guard url.scheme == "arcfin" else { return }
        guard isPastLock else {
            heldLinks.append(url)
            return
        }
        switch url.host {
        case "play":
            // arcfin://play/<itemId>. Buffered for a cold launch: Home reads it after loading.
            guard let itemID = url.pathComponents.dropFirst().first else { return }
            UserDefaults.standard.set(itemID, forKey: "arcfin.pendingPlayID")
            NotificationCenter.default.post(name: .arcfinPlayItem, object: nil, userInfo: ["itemID": itemID])
        case "downloads":
            // Buffered too: the Browse tab that shows Downloads may not be mounted yet.
            UserDefaults.standard.set(true, forKey: "arcfin.pendingShowDownloads")
            NotificationCenter.default.post(name: .arcfinShowDownloads, object: nil)
        case "remote":
            // arcfin://remote/<sessionId>, from the Live Activity for another device playing.
            AppServices.remoteSessions.selectedID = url.pathComponents.dropFirst().first
            AppServices.remoteSessions.open()
        case "pick":
            // arcfin://pick/<code>?server=…, from a Pick Together share link. Buffered for a
            // cold launch: Home reads it once it's up.
            guard let code = url.pathComponents.dropFirst().first else { return }
            UserDefaults.standard.set(code, forKey: "arcfin.pendingPickCode")
            NotificationCenter.default.post(name: .arcfinPickTogether, object: nil, userInfo: ["code": code])
        case "party":
            // arcfin://party/<code>, from a watch party's QR code. Buffered like "pick".
            guard let code = url.pathComponents.dropFirst().first else { return }
            UserDefaults.standard.set(code, forKey: "arcfin.pendingPartyCode")
            NotificationCenter.default.post(name: .arcfinWatchParty, object: nil, userInfo: ["code": code])
        case "resume":
            UserDefaults.standard.set(true, forKey: "arcfin.pendingResume")
            NotificationCenter.default.post(name: .arcfinResume, object: nil)
        default:
            handleRoutingLink(url)
        }
    }

    /// Through the lock screen's profile picker, so a PIN on another profile still applies.
    func switchProfileFromSchedule() {
        isAppLocked = true
    }

    /// Raises the lock over what's open. Covered by a screen of the signed-in tree, which
    /// would stay above the lock, the tree is closed instead.
    func lockKeepingContent(_ keepsContent: Bool) {
        keepsContentUnderLock = keepsContent && isPastLock
        lockedProfileID = authManager.state.credential?.id
        isAppLocked = true
        AppServices.hasPassedLock = false
    }

    func unlock() {
        if keepsContentUnderLock, lockedProfileID != authManager.state.credential?.id { contentGeneration += 1 }
        isAppLocked = false
        keepsContentUnderLock = false
        AppServices.hasPassedLock = true
        runHeldRoutes()
    }

    /// The lock is decided and open in this window. Until then the signed-in screens aren't
    /// built, so nothing of the profile's can be reached, or open above the lock.
    var isPastLock: Bool { launchChecked && !isAppLocked }

    /// Whether the phase's screens are built: the signed-in ones once the lock is decided and
    /// open, or kept under a lock raised over them; offline Downloads while it isn't up.
    func showsContent(_ phase: AppPhase) -> Bool {
        switch phase {
        case .main: isPastLock || keepsContentUnderLock
        case .offline: !isAppLocked
        default: true
        }
    }

    /// Links, Siri and controls that waited for the lock, and Play On sent meanwhile.
    private func runHeldRoutes() {
        let links = heldLinks
        heldLinks = []
        links.forEach(handleDeepLink)
        runPendingRoutes()
        RemoteControl.shared.runHeld()
        MusicSharePlay.shared.runHeld()
    }

    /// Apple TV's Who's Watching on a return: asked then or not at all, over the screens as
    /// they were.
    func askWhoIsWatchingOnReturn(secondsAway: TimeInterval, keepsContent: Bool) {
        guard isPastLock, authManager.state.credential != nil,
              WhoIsWatching.shouldAsk(isOn: WhoIsWatching.isOn, profileCount: authManager.profiles.count,
                                      isColdLaunch: false, secondsAway: secondsAway,
                                      isPlayerOpen: PlayerActivity.shared.isPlayerOpen,
                                      isMusicPlaying: AppServices.music.isPlaying)
        else { return }
        lockKeepingContent(keepsContent)
    }

    func loadProfileRules() async {
        guard let credential = authManager.state.credential else { return }
        await ProfileRules.shared.load(credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken))
    }

    /// Siri's Download Next Episode, once there's a signed-in profile to download with.
    func startPendingDownload() {
        guard isPastLock, let credential = authManager.state.credential,
              let id = UserDefaults.standard.string(forKey: DownloadRoute.pendingKey) else { return }
        UserDefaults.standard.removeObject(forKey: DownloadRoute.pendingKey)
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        Task {
            guard let item = try? await JellyfinMediaClient().getItemDetail(credential: credential, authHeader: header, itemId: id).item
            else { return }
            await downloadManager.startDownload(item: item, credential: credential, authHeader: header, bitrateCap: DownloadQuality.saved.tier)
        }
    }

    /// The stored sign-in and the PIN lock, checked once at launch.
    func checkLaunch() async {
        await authManager.checkStoredAuthOnce()
        await refreshLockRequirement()
        let asksWhoIsWatching = authManager.state.credential != nil
            && WhoIsWatching.asksAtLaunch(profileCount: authManager.profiles.count)
        if activeProfileHasPIN || asksWhoIsWatching { isAppLocked = true } else { AppServices.hasPassedLock = true }
        launchChecked = true
        if !isAppLocked { runHeldRoutes() }
    }

    /// The tour and What's New wait for the splash, the sign-in check and the PIN lock, and
    /// stay out of the way of a player.
    func isShowing(_ presentation: AppIntroduction.Presentation, phase: AppPhase) -> Bool {
        guard introduction.presentation == presentation, splashDone, launchChecked, !isAppLocked
        else { return false }
        if playerCoversWindow { return false }
        return phase == .login || phase == .main || phase == .offline
    }

    /// Whether Ask First can ask about settings changed on another device. Like What's New it
    /// waits for the splash and the lock, and never comes up over a player or the tour.
    func canAskAboutRemoteSettings(phase: AppPhase) -> Bool {
        authManager.pendingRemoteSettings != nil && phase == .main && splashDone && isPastLock
            && introduction.presentation == nil && !playerCoversWindow && !PlayerActivity.shared.isPlayerOpen
    }

    /// Any way the presentation closes counts as seen, a swipe down or Menu included.
    func introductionBinding(_ presentation: AppIntroduction.Presentation, phase: AppPhase) -> Binding<Bool> {
        Binding(
            get: { self.isShowing(presentation, phase: phase) },
            set: { shown in
                guard !shown, self.introduction.presentation == presentation else { return }
                switch presentation {
                case .onboarding: self.introduction.finishOnboarding()
                case .whatsNew: self.introduction.finishWhatsNew()
                }
            }
        )
    }

    private func seerrSetupPromptHandledKey(for credentialID: UUID) -> String {
        "arcfin.seerrSetupPromptHandled.\(credentialID.uuidString)"
    }

    func markSeerrSetupPromptHandled(for credentialID: UUID) {
        UserDefaults.standard.set(true, forKey: seerrSetupPromptHandledKey(for: credentialID))
    }

    /// The server's Arcfin Sync plugin gave a Seerr address but this profile hasn't connected
    /// Seerr: connect it with the Jellyfin account through Quick Connect, without asking. Only
    /// when that can't work does the prompt appear, asking for the password and saying why.
    func checkSeerrSetupPrompt(seerrURL: String, seerrUsername: String, seerrAuthMethod: SeerrAuthMethod) {
        guard case .authenticated(let cred) = authManager.state,
              seerrAuthMethod.isJellyfin, !seerrURL.isEmpty, let url = URL(string: seerrURL),
              seerrUsername.isEmpty, !isConnectingSeerr,
              !UserDefaults.standard.bool(forKey: seerrSetupPromptHandledKey(for: cred.id))
        else { return }
        isConnectingSeerr = true
        let client = SeerrHTTPClient(baseURL: url, username: cred.displayName, password: "", authMethod: .jellyfin,
                                     authorizeQuickConnect: SeerrSignIn.quickConnectAuthorizer(authManager: authManager))
        Task {
            defer { isConnectingSeerr = false }
            do {
                try await client.login()
                guard authManager.state.credential?.id == cred.id else { return }
                authManager.removeSeerrPassword()
                UserDefaults.standard.set(cred.displayName, forKey: "seerrUsername")
                markSeerrSetupPromptHandled(for: cred.id)
            } catch where SeerrRepository.isCancellation(error) {
            } catch {
                guard authManager.state.credential?.id == cred.id else { return }
                seerrSetupError = SeerrSignInText.message(for: error)
                showSeerrSetupPrompt = true
            }
        }
    }

    func refreshLockRequirement() async {
        if authManager.signOutsToNextProfile != handledSignOuts {
            handledSignOuts = authManager.signOutsToNextProfile
            isAppLocked = true
            keepsContentUnderLock = false
        }
        guard case .authenticated(let cred) = authManager.state else {
            activeProfileHasPIN = false
            // The last profile signed out from the lock screen: the sign-in screen comes next,
            // and links meant for that profile go with it.
            if authManager.profiles.isEmpty, isAppLocked {
                isAppLocked = false
                keepsContentUnderLock = false
                heldLinks = []
            }
            return
        }
        activeProfileHasPIN = await authManager.storedPIN(for: cred.id) != .none
    }

    func syncOfflineProgress(modelContext: ModelContext) {
        guard case .authenticated = authManager.state else { return }
        let profiles = authManager.profiles
        let authClient = authManager.authClient
        Task {
            await OfflineProgressSync.syncPending(
                modelContext: modelContext, profiles: profiles,
                authHeader: { authClient.authHeader(token: $0.accessToken) }
            )
        }
    }

    /// Back in the app: the heartbeat, Arcfin Sync and Seerr loops start; once no window is
    /// in front they stop.
    func scenePhaseChanged(to newPhase: ScenePhase) {
        if newPhase == .active {
            Task { await authManager.checkSignInStillValid() }
            startHeartbeat()
            startArcfinSyncLoop()
            startSeerrPollLoop()
            // Control Center, Notification Center and Picture in Picture each pass through the
            // background too, so the heavier refreshes wait a few minutes between returns.
            if Self.lastForegroundRefresh.map({ Date().timeIntervalSince($0) > 5 * 60 }) ?? true {
                Self.lastForegroundRefresh = Date()
                authManager.syncArcfinNow()
                Task { await loadProfileRules() }
                Task { await MusicDownloads.shared.refreshSmartDownloads() }
            }
        } else if !AppServices.scenes.anyActive {
            Self.heartbeatTask?.cancel()
            Self.arcfinSyncTask?.cancel()
            Self.seerrPollTask?.cancel()
        }
    }

    /// Jellyfin marks a session "active" from any authenticated request — the app's own
    /// normal API traffic keeps that fresh while actively browsing, but a lightweight
    /// periodic ping covers idle stretches (paused on a detail screen, backgrounded briefly)
    /// so the server's Active Devices view doesn't show a stale/offline session.
    private func startHeartbeat() {
        Self.heartbeatTask?.cancel()
        // Sleeps first: becoming active already checks the sign-in.
        Self.heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                if case .authenticated(let cred) = authManager.state {
                    _ = await authManager.authClient.validateToken(credential: cred)
                }
            }
        }
    }

    /// Cold launch and every sign-in/profile-switch already trigger a sync (see
    /// AuthManager.refreshArcfinSync's call sites). This covers the gap: an admin changing a
    /// lock or prefill while a user's app is already open shouldn't need a restart to take
    /// effect. 15 minutes, not 60 seconds like the heartbeat — this hits a real endpoint that
    /// reads/writes a file per user, no need for it to be as cheap/frequent as a token check.
    private func startArcfinSyncLoop() {
        Self.arcfinSyncTask?.cancel()
        Self.arcfinSyncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                guard !Task.isCancelled else { return }
                authManager.syncArcfinNow()
            }
        }
    }

    /// Polls Seerr requests while the app is active so a status change (approved, now
    /// available) can fire a local notification — loadRequests() itself only runs this
    /// diff on a refresh, never the first load, so an app that's never polled before doesn't
    /// notify for everything already sitting at approved/available. 5 minutes: more time-
    /// sensitive than the Arcfin Sync loop above (a user actually wants to know promptly),
    /// but still a real per-user Seerr request, not worth a sub-minute cadence.
    private func startSeerrPollLoop() {
        Self.seerrPollTask?.cancel()
        guard seerrRepo.isConfigured else { return }
        Self.seerrPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await seerrRepo.loadRequests()
            }
        }
    }

    func configureSeerr(seerrURL: String, seerrUsername: String, seerrAuthMethod: SeerrAuthMethod) {
        Self.connectSeerr(seerrURL: seerrURL, seerrUsername: seerrUsername, seerrAuthMethod: seerrAuthMethod,
                          seerrRepo: seerrRepo, authManager: authManager)
    }

    /// The saved Seerr connection, read again: when the server starts or stops offering Seerr.
    static func reconnectSeerr() {
        let defaults = UserDefaults.standard
        connectSeerr(seerrURL: defaults.string(forKey: "seerrURL") ?? "",
                     seerrUsername: defaults.string(forKey: "seerrUsername") ?? "",
                     seerrAuthMethod: defaults.string(forKey: "seerrAuthMethod").flatMap(SeerrAuthMethod.init(rawValue:)) ?? .jellyfin,
                     seerrRepo: AppServices.seerrRepo, authManager: AppServices.authManager)
    }

    private static func connectSeerr(seerrURL: String, seerrUsername: String, seerrAuthMethod: SeerrAuthMethod,
                                     seerrRepo: SeerrRepository, authManager: AuthManager) {
        // The server's Arcfin Sync plugin has a Seerr key: always that, nothing to sign in to.
        if ServerCompanion.shared.integrations.seerr, case .authenticated(let credential) = authManager.state {
            seerrRepo.configureThroughServer(credential: credential,
                                             authorization: authManager.authClient.authHeader(token: credential.accessToken))
        } else {
            seerrRepo.configure(urlString: seerrURL, username: seerrUsername,
                                password: authManager.seerrPassword, authMethod: seerrAuthMethod,
                                authorizeQuickConnect: SeerrSignIn.quickConnectAuthorizer(authManager: authManager),
                                onSavedPasswordRejected: { [authManager] in await authManager.removeSeerrPassword() })
        }
        // Warms Discover and the Browse > Your Requests sections in the background as soon
        // as Seerr is reachable, so they're already populated (no skeleton) the first time
        // the user actually taps into either.
        guard seerrRepo.isConfigured else { return }
        Task {
            await seerrRepo.loadDiscover()
            await seerrRepo.loadRequests()
        }
    }
}

extension EnvironmentValues {
    /// The screens are kept, hidden, under the lock: nothing in them may play or open.
    @Entry var isBehindLock = false
}
