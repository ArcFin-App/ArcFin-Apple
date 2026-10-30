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
    var activeProfileHasPIN = false
    /// The stored sign-in and the PIN lock have been checked this launch.
    var launchChecked = false
    var showSeerrSetupPrompt = false
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var arcfinSyncTask: Task<Void, Never>?
    @ObservationIgnored private var seerrPollTask: Task<Void, Never>?

    /// Routes an arcfin:// link from a widget, Live Activity, the Top Shelf or a control.
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "arcfin" else { return }
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

    func unlock() {
        isAppLocked = false
        AppServices.hasPassedLock = true
    }

    func loadProfileRules() async {
        guard let credential = authManager.state.credential else { return }
        await ProfileRules.shared.load(credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken))
    }

    /// Siri's Download Next Episode, once there's a signed-in profile to download with.
    func startPendingDownload() {
        guard let credential = authManager.state.credential,
              let id = UserDefaults.standard.string(forKey: DownloadRoute.pendingKey) else { return }
        UserDefaults.standard.removeObject(forKey: DownloadRoute.pendingKey)
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        Task {
            guard let item = try? await JellyfinMediaClient().getItemDetail(credential: credential, authHeader: header, itemId: id).item
            else { return }
            await downloadManager.startDownload(item: item, credential: credential, authHeader: header)
        }
    }

    /// The stored sign-in and the PIN lock, checked once at launch.
    func checkLaunch() async {
        await authManager.checkStoredAuth()
        await refreshLockRequirement()
        if activeProfileHasPIN { isAppLocked = true } else { AppServices.hasPassedLock = true }
        launchChecked = true
        runPendingRoutes()
    }

    /// The tour and What's New wait for the splash, the sign-in check and the PIN lock, and
    /// stay out of the way of a player.
    func isShowing(_ presentation: AppIntroduction.Presentation, phase: AppPhase) -> Bool {
        guard introduction.presentation == presentation, splashDone, launchChecked, !isAppLocked
        else { return false }
        if playerCoversWindow { return false }
        return phase == .login || phase == .main || phase == .offline
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

    func checkSeerrSetupPrompt(seerrURL: String, seerrUsername: String, seerrAuthMethod: SeerrAuthMethod) {
        guard case .authenticated(let cred) = authManager.state,
              authManager.arcfinSyncLockedKeys.contains("seerrAuthMethod"),
              seerrAuthMethod == .jellyfin, !seerrURL.isEmpty,
              seerrUsername.isEmpty || authManager.seerrPassword.isEmpty,
              !UserDefaults.standard.bool(forKey: seerrSetupPromptHandledKey(for: cred.id))
        else { return }
        showSeerrSetupPrompt = true
    }

    func refreshLockRequirement() async {
        guard case .authenticated(let cred) = authManager.state else {
            activeProfileHasPIN = false
            return
        }
        activeProfileHasPIN = await authManager.pin(for: cred.id) != nil
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

    /// Back in the app: the heartbeat, Arcfin Sync and Seerr loops start; leaving stops them.
    func scenePhaseChanged(to newPhase: ScenePhase) {
        if newPhase == .active {
            Task { await authManager.checkSignInStillValid() }
            startHeartbeat()
            startArcfinSyncLoop()
            authManager.syncArcfinNow()
            startSeerrPollLoop()
        } else {
            heartbeatTask?.cancel()
            arcfinSyncTask?.cancel()
            seerrPollTask?.cancel()
        }
    }

    /// Jellyfin marks a session "active" from any authenticated request — the app's own
    /// normal API traffic keeps that fresh while actively browsing, but a lightweight
    /// periodic ping covers idle stretches (paused on a detail screen, backgrounded briefly)
    /// so the server's Active Devices view doesn't show a stale/offline session.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                if case .authenticated(let cred) = authManager.state {
                    _ = await authManager.authClient.validateToken(credential: cred)
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Cold launch and every sign-in/profile-switch already trigger a sync (see
    /// AuthManager.refreshArcfinSync's call sites). This covers the gap: an admin changing a
    /// lock or prefill while a user's app is already open shouldn't need a restart to take
    /// effect. 15 minutes, not 60 seconds like the heartbeat — this hits a real endpoint that
    /// reads/writes a file per user, no need for it to be as cheap/frequent as a token check.
    private func startArcfinSyncLoop() {
        arcfinSyncTask?.cancel()
        arcfinSyncTask = Task {
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
        seerrPollTask?.cancel()
        guard seerrRepo.isConfigured else { return }
        seerrPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                await seerrRepo.loadRequests()
            }
        }
    }

    func configureSeerr(seerrURL: String, seerrUsername: String, seerrAuthMethod: SeerrAuthMethod) {
        seerrRepo.configure(urlString: seerrURL, username: seerrUsername,
                            password: authManager.seerrPassword, authMethod: seerrAuthMethod)
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
