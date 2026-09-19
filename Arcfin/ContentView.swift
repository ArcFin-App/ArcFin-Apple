import SwiftUI
import SwiftData
import AuthCore
import JellyfinAPI
import Persistence
import SeerrAPI
import SyncEngine

private enum AppPhase: Equatable {
    case splash, login, main, offline
}

// Posted by onOpenURL when the Top Shelf launches a play deep link.
extension Notification.Name {
    static let arcfinPlayItem = Notification.Name("arcfinPlayItem")
    /// Posted by onOpenURL for arcfin://downloads — tapping the download Live Activity.
    static let arcfinShowDownloads = Notification.Name("arcfinShowDownloads")
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @State private var authManager  = AuthManager()
    @State private var mediaRepo    = MediaRepository()
    @State private var seerrRepo    = SeerrRepository()
    @State private var statsRepo    = StreamystatsRepository()
    @State private var downloadManager = DownloadManager()
    @State private var syncPlayManager = SyncPlayManager()
    @State private var splashDone   = false
    @State private var heartbeatTask: Task<Void, Never>?
    #if os(iOS)
    @State private var showOfflineDocPicker = false
    @State private var offlinePickedURL: URL?
    @State private var navigateToOfflineLocalPlayer = false
    #endif

    @AppStorage("seerrURL")          private var seerrURL         = ""
    @AppStorage("seerrUsername")     private var seerrUsername    = ""
    @AppStorage("seerrPassword")     private var seerrPassword    = ""
    @AppStorage("seerrAuthMethod")   private var seerrAuthMethod  = SeerrAuthMethod.jellyfin
    @AppStorage("streamystatsURL")   private var statsURL         = ""
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false

    private var phase: AppPhase {
        guard splashDone else { return .splash }
        if offlineModeEnabled { return .offline }
        switch authManager.state {
        case .authenticated:   return .main
        case .unauthenticated: return .login
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView(isLoading: authManager.isChecking) { splashDone = true }
                    .transition(.opacity)
            case .login:
                LoginRootView()
                    .transition(.opacity)
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
        .animation(DT.Animation.standard, value: phase)
        .preferredColorScheme(.dark)
#if os(tvOS)
        .focusEffectDisabled()
#endif
        .environment(authManager)
        .environment(mediaRepo)
        .environment(seerrRepo)
        .environment(statsRepo)
        .environment(downloadManager)
        .environment(syncPlayManager)
        .onOpenURL { url in
            guard url.scheme == "arcfin" else { return }
            switch url.host {
            case "play":
                // arcfin://play/<itemId> — from Top Shelf or Siri
                guard let itemID = url.pathComponents.dropFirst().first else { return }
                // Buffer for cold-launch: HomeView .task reads this after mediaRepo.load()
                UserDefaults.standard.set(itemID, forKey: "arcfin.pendingPlayID")
                // Also post for warm/already-running case
                NotificationCenter.default.post(
                    name: .arcfinPlayItem,
                    object: nil,
                    userInfo: ["itemID": itemID]
                )
            case "downloads":
                // arcfin://downloads — tapping the download Live Activity.
                NotificationCenter.default.post(name: .arcfinShowDownloads, object: nil)
            default:
                break
            }
        }
        .task { await authManager.checkStoredAuth() }
        .task { authManager.startNetworkMonitoring() }
        .task { downloadManager.configure(modelContext: modelContext) }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { startHeartbeat() } else { heartbeatTask?.cancel() }
        }
        .onAppear { configureSeerr() }
        .onChange(of: seerrURL)        { configureSeerr() }
        .onChange(of: seerrUsername)   { configureSeerr() }
        .onChange(of: seerrPassword)   { configureSeerr() }
        .onChange(of: seerrAuthMethod) { configureSeerr() }
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
    }

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

    private func configureSeerr() {
        seerrRepo.configure(urlString: seerrURL, username: seerrUsername,
                            password: seerrPassword, authMethod: seerrAuthMethod)
        // Warms the Requests tab in the background as soon as Seerr is reachable, so it's
        // already populated (no skeleton) the first time the user actually taps that tab.
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
