import SwiftUI
import AuthCore
import SeerrAPI

private enum AppPhase: Equatable {
    case splash, login, main
}

// Posted by onOpenURL when the Top Shelf launches a play deep link.
extension Notification.Name {
    static let arcfinPlayItem = Notification.Name("arcfinPlayItem")
}

struct ContentView: View {
    @State private var authManager  = AuthManager()
    @State private var mediaRepo    = MediaRepository()
    @State private var seerrRepo    = SeerrRepository()
    @State private var statsRepo    = StreamystatsRepository()
    @State private var splashDone   = false

    @AppStorage("seerrURL")          private var seerrURL         = ""
    @AppStorage("seerrUsername")     private var seerrUsername    = ""
    @AppStorage("seerrPassword")     private var seerrPassword    = ""
    @AppStorage("seerrAuthMethod")   private var seerrAuthMethod  = SeerrAuthMethod.jellyfin
    @AppStorage("streamystatsURL")   private var statsURL         = ""

    private var phase: AppPhase {
        guard splashDone && !authManager.isChecking else { return .splash }
        switch authManager.state {
        case .authenticated:   return .main
        case .unauthenticated: return .login
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView { splashDone = true }
                    .transition(.opacity)
            case .login:
                LoginRootView()
                    .transition(.opacity)
            case .main:
                MainTabView()
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
        .onOpenURL { url in
            // arcfin://play/<itemId>  — from Top Shelf or Siri
            guard url.scheme == "arcfin",
                  url.host == "play",
                  let itemID = url.pathComponents.dropFirst().first
            else { return }
            // Buffer for cold-launch: HomeView .task reads this after mediaRepo.load()
            UserDefaults.standard.set(itemID, forKey: "arcfin.pendingPlayID")
            // Also post for warm/already-running case
            NotificationCenter.default.post(
                name: .arcfinPlayItem,
                object: nil,
                userInfo: ["itemID": itemID]
            )
        }
        .task { await authManager.checkStoredAuth() }
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
    }

    private func configureSeerr() {
        seerrRepo.configure(urlString: seerrURL, username: seerrUsername,
                            password: seerrPassword, authMethod: seerrAuthMethod)
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
