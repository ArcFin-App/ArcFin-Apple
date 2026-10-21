// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import AuthCore
import JellyfinAPI
import Persistence
import SeerrAPI
import SyncEngine

private enum AppPhase: Equatable {
    case splash, login, main, offline
    #if os(iOS)
    // SplashView always exits after its own fixed minimum presentation time regardless of
    // whether checkStoredAuth() has concluded, so a slow network previously meant the app
    // dropped straight to the Login screen while an already-valid session was still being
    // confirmed in the background.
    case checkingSession
    #endif
}

// Posted by onOpenURL when the Top Shelf launches a play deep link.
extension Notification.Name {
    static let arcfinPlayItem = Notification.Name("arcfinPlayItem")
    /// Posted by onOpenURL for arcfin://downloads — tapping the download Live Activity.
    static let arcfinShowDownloads = Notification.Name("arcfinShowDownloads")
    /// Posted by onOpenURL for arcfin://resume — the Resume Watching control.
    static let arcfinResume = Notification.Name("arcfinResume")
    /// Posted when a notification about a Seerr request or watchlist item is tapped.
    static let arcfinShowDiscover = Notification.Name("arcfinShowDiscover")
    /// Posted with a "term" in userInfo to show in-app search results (Siri / Shortcuts).
    static let arcfinSearch = Notification.Name("arcfinSearch")
    /// Posted with an "id" (Seerr entry id) to open that title's Seerr page.
    static let arcfinOpenSeerrTitle = Notification.Name("arcfinOpenSeerrTitle")
    /// Posted when the user switches away from the Home tab, so a shuffled Home can reorder
    /// itself while it is off-screen.
    static let arcfinHomeTabLeft = Notification.Name("arcfinHomeTabLeft")
    /// Posted by the macOS app menu's Settings… command (Cmd+,) — there's no scene-level
    /// binding into MainTabView's private navigation state to reach otherwise, so this
    /// follows the same NotificationCenter pattern arcfinShowDownloads already established.
    static let arcfinShowSettings = Notification.Name("arcfinShowSettings")
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @State private var authManager  = AuthManager()
    @State private var mediaRepo    = MediaRepository()
    @State private var playbackPresenter = PlaybackPresenter()
    @State private var seerrRepo    = SeerrRepository()
    @State private var statsRepo    = StreamystatsRepository()
    @State private var downloadManager = DownloadManager()
    @State private var syncPlayManager = SyncPlayManager()
    @State private var splashDone   = false
    @State private var heartbeatTask: Task<Void, Never>?
    @State private var arcfinSyncTask: Task<Void, Never>?
    @State private var seerrPollTask: Task<Void, Never>?
    #if !os(tvOS)
    @State private var isAppLocked = false
    @State private var activeProfileHasPIN = false
    @AppStorage("appLockUseFaceID") private var appLockUseFaceID = true
    #endif
    #if os(iOS)
    @State private var showOfflineDocPicker = false
    @State private var offlinePickedURL: URL?
    @State private var navigateToOfflineLocalPlayer = false
    @State private var bypassSessionCheck = false
    #endif

    @AppStorage("seerrURL")          private var seerrURL         = ""
    @AppStorage("seerrUsername")     private var seerrUsername    = ""
    @AppStorage("seerrAuthMethod")   private var seerrAuthMethod  = SeerrAuthMethod.jellyfin
    @AppStorage("streamystatsURL")   private var statsURL         = ""
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    @State private var showSeerrSetupPrompt = false

    /// Routes an arcfin:// link from a widget, Live Activity, the Top Shelf or a control.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "arcfin" else { return }
        switch url.host {
        case "play":
            // arcfin://play/<itemId>. Buffered for a cold launch: Home reads it after loading.
            guard let itemID = url.pathComponents.dropFirst().first else { return }
            UserDefaults.standard.set(itemID, forKey: "arcfin.pendingPlayID")
            NotificationCenter.default.post(name: .arcfinPlayItem, object: nil, userInfo: ["itemID": itemID])
        case "downloads":
            // Buffered too: the Browse tab that shows Downloads may not be mounted yet.
            UserDefaults.standard.set(true, forKey: "arcfin.pendingDownloads")
            NotificationCenter.default.post(name: .arcfinShowDownloads, object: nil)
        case "resume":
            UserDefaults.standard.set(true, forKey: "arcfin.pendingResume")
            NotificationCenter.default.post(name: .arcfinResume, object: nil)
        #if os(iOS)
        case "discover":
            ArcfinRouting.showDiscover()
        case "search":
            ArcfinRouting.search(url.pathComponents.dropFirst().first ?? "")
        #endif
        default:
            break
        }
    }

    #if os(iOS)
    private func consumeControlLink() {
        guard let link = UserDefaults.standard.string(forKey: ControlRoute.pendingKey), let url = URL(string: link) else { return }
        UserDefaults.standard.removeObject(forKey: ControlRoute.pendingKey)
        handleDeepLink(url)
    }
    #endif

    private var phase: AppPhase {
        guard splashDone else { return .splash }
        if offlineModeEnabled { return .offline }
        #if os(iOS)
        if !bypassSessionCheck, authManager.isChecking, authManager.state == .unauthenticated {
            return .checkingSession
        }
        #endif
        switch authManager.state {
        case .authenticated:   return .main
        case .unauthenticated: return .login
        }
    }

    // Extracted out of body — one giant ZStack combining this switch, the overlay ifs
    // below, and body's own long modifier chain made the whole expression too much for
    // the type checker to resolve in reasonable time. Splitting it into its own
    // @ViewBuilder gives the compiler a much smaller expression to solve on its own.
    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .splash:
            SplashView(isLoading: authManager.isChecking) { splashDone = true }
                .transition(.opacity)
        case .login:
            LoginRootView()
                .transition(.opacity)
        #if os(iOS)
        case .checkingSession:
            SessionCheckingView(
                onSignInManually: { bypassSessionCheck = true },
                onGoOffline: { offlineModeEnabled = true }
            )
            .transition(.opacity)
        #endif
        case .main:
            MainTabView()
                .transition(.opacity)
        case .offline:
            NavigationStack {
                DownloadsView(goBackOnline: { offlineModeEnabled = false })
                    #if os(iOS)
                    // Offline mode replaces the whole app with DownloadsView, which
                    // previously had no way to reach "On This Device" — the only local
                    // playback option left offline was Jellyfin downloads themselves.
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showOfflineDocPicker = true } label: {
                                Image(systemName: "folder")
                            }
                            .accessibilityLabel("Open local file")
                        }
                    }
                    .sheet(isPresented: $showOfflineDocPicker) {
                        DocumentPickerView { url in
                            offlinePickedURL = url
                            navigateToOfflineLocalPlayer = true
                        }
                    }
                    .navigationDestination(isPresented: $navigateToOfflineLocalPlayer) {
                        if let url = offlinePickedURL {
                            LocalPlayerView(url: url)
                                .toolbar(.hidden, for: .tabBar)
                        }
                    }
                    #endif
            }
            .transition(.opacity)
        }
    }

    var body: some View {
        ZStack {
            phaseContent

            #if !os(tvOS)
            if isAppLocked {
                AppLockView(useFaceID: appLockUseFaceID) { isAppLocked = false }
                    .transition(.opacity)
                    .zIndex(10)
            }
            #endif

            #if os(macOS)
            // A .sheet on macOS is an inherently small, modal, parent-attached panel — it
            // can't properly fill or fullscreen a window, which is exactly why the player
            // looked stuck small with a non-functional fullscreen button. This mirrors
            // AppLockView's own full-window overlay pattern instead: real window-filling
            // content, and a real working NSWindow-level fullscreen. iOS/tvOS are untouched
            // and keep using their existing per-screen .fullScreenCover.
            if let request = playbackPresenter.request {
                PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                    playbackPresenter.present(next, onPlayNext: request.onPlayNext)
                }
                .transition(.opacity)
                .zIndex(20)
            }
            #endif
        }
        .animation(DT.Animation.standard, value: phase)
        #if !os(tvOS)
        .animation(DT.Animation.standard, value: isAppLocked)
        #endif
        .preferredColorScheme(.dark)
#if os(tvOS)
        .focusEffectDisabled()
#endif
        .environment(authManager)
        .environment(mediaRepo)
        .environment(playbackPresenter)
        .environment(seerrRepo)
        .environment(statsRepo)
        .environment(downloadManager)
        .environment(syncPlayManager)
        .onOpenURL { handleDeepLink($0) }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: ControlRoute.notification)) { _ in
            consumeControlLink()
        }
        #endif
        .task {
            await authManager.checkStoredAuth()
            #if !os(tvOS)
            await refreshLockRequirement()
            if activeProfileHasPIN { isAppLocked = true }
            #endif
            #if os(iOS)
            consumeControlLink()
            #endif
        }
        .task { authManager.startNetworkMonitoring() }
        .task { downloadManager.configure(modelContext: modelContext, authManager: authManager) }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                startHeartbeat()
                startArcfinSyncLoop()
                authManager.syncArcfinNow()
                startSeerrPollLoop()
            } else {
                heartbeatTask?.cancel()
                arcfinSyncTask?.cancel()
                seerrPollTask?.cancel()
            }
            // Deliberately no re-lock here. scenePhase drops to .background not just when
            // the app is actually left, but also pulling down Notification/Control Center
            // over it and entering Picture in Picture (the app's own UI is off-screen, so
            // the system backgrounds the scene) — locking on every one of those made the
            // PIN/Face ID prompt reappear on nearly every interaction. The PIN/Face ID
            // gate now only ever applies at cold launch (see the initial .task above).
            #if os(iOS)
            // NWPathMonitor's callback can be suspended along with the rest of the app while
            // backgrounded and doesn't reliably fire again the instant it resumes — coming
            // back to the foreground is exactly when the network is most likely to have
            // actually changed (left/rejoined home Wi-Fi, Wi-Fi toggled off entirely) without
            // Arcfin having noticed yet.
            if newPhase == .active {
                Task { await authManager.reresolveBaseURLIfNeeded() }
                downloadManager.refreshSmartDownloads()
            }
            #endif
        }
        #if !os(tvOS)
        .onChange(of: authManager.state) { _, _ in Task { await refreshLockRequirement() } }
        #endif
        .onAppear { configureSeerr() }
        .onChange(of: seerrURL)        { configureSeerr() }
        .onChange(of: seerrUsername)   { configureSeerr() }
        .onChange(of: authManager.seerrPassword) { configureSeerr() }
        .onChange(of: seerrAuthMethod) { configureSeerr() }
        // A profile switch keeps the same Seerr URL/username/password today, so
        // configureSeerr() above would just no-op as "nothing changed" — this instead clears
        // any stuck auth-failure cooldown and retries directly (see
        // SeerrRepository.retryAfterProfileSwitch).
        .onChange(of: authManager.state) { Task { await seerrRepo.retryAfterProfileSwitch() } }
        // Streamystats is reconfigured after load() sets serverID + we have the token
        .onChange(of: mediaRepo.serverID) { configureStats() }
        .onChange(of: statsURL)           { configureStats() }
        // A profile switch keeps the same serverID when staying on one server, so
        // Streamystats needs its own trigger to pick up the new credential's token.
        .onChange(of: authManager.state)  { configureStats() }
        .onChange(of: authManager.state) { _, newState in
            if case .authenticated = newState { syncOfflineProgress() }
        }
        // The explicit "I'm back online" moment — items played while offline sync then too,
        // not just at next cold launch.
        .onChange(of: offlineModeEnabled) { _, isOffline in
            if !isOffline { syncOfflineProgress() }
        }
        // Quick Connect sign-in has no password to auto-fill Seerr with (see AuthView's
        // attemptSeerrAutoLogin, which only runs on the password-based path) — once a sync
        // confirms Seerr is locked to a Jellyfin account server-side but this profile still
        // has no Seerr credential, offer to connect it interactively instead of leaving it
        // silently broken with no way to fix it (Settings hides the fields while locked).
        .onChange(of: authManager.isSyncingArcfin) { _, isSyncing in
            if !isSyncing { checkSeerrSetupPrompt() }
        }
        .sheet(isPresented: $showSeerrSetupPrompt) {
            if case .authenticated(let cred) = authManager.state {
                SeerrSetupPromptView(
                    seerrURL: seerrURL,
                    jellyfinUsername: cred.displayName,
                    onConnected: { username, password in
                        seerrUsername = username
                        authManager.saveSeerrPassword(password)
                        markSeerrSetupPromptHandled(for: cred.id)
                    },
                    onDismiss: { markSeerrSetupPromptHandled(for: cred.id) }
                )
            }
        }
    }

    private func seerrSetupPromptHandledKey(for credentialID: UUID) -> String {
        "arcfin.seerrSetupPromptHandled.\(credentialID.uuidString)"
    }

    private func markSeerrSetupPromptHandled(for credentialID: UUID) {
        UserDefaults.standard.set(true, forKey: seerrSetupPromptHandledKey(for: credentialID))
    }

    private func checkSeerrSetupPrompt() {
        guard case .authenticated(let cred) = authManager.state,
              authManager.arcfinSyncLockedKeys.contains("seerrAuthMethod"),
              seerrAuthMethod == .jellyfin, !seerrURL.isEmpty,
              seerrUsername.isEmpty || authManager.seerrPassword.isEmpty,
              !UserDefaults.standard.bool(forKey: seerrSetupPromptHandledKey(for: cred.id))
        else { return }
        showSeerrSetupPrompt = true
    }

    #if !os(tvOS)
    private func refreshLockRequirement() async {
        guard case .authenticated(let cred) = authManager.state else {
            activeProfileHasPIN = false
            return
        }
        activeProfileHasPIN = await authManager.pin(for: cred.id) != nil
    }
    #endif

    private func syncOfflineProgress() {
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

    private func configureSeerr() {
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

    private func configureStats() {
        guard case .authenticated(let cred) = authManager.state,
              !mediaRepo.serverID.isEmpty else { return }
        statsRepo.configure(urlString: statsURL, credential: cred, serverId: mediaRepo.serverID)
    }
}

#Preview {
    ContentView()
}
