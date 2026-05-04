import SwiftUI
import AuthCore
import JellyseerrAPI

private enum AppPhase: Equatable {
    case splash, login, main
}

struct ContentView: View {
    @State private var authManager  = AuthManager()
    @State private var mediaRepo    = MediaRepository()
    @State private var seerrRepo    = JellyseerrRepository()
    @State private var statsRepo    = StreamystatsRepository()
    @State private var splashDone   = false

    @AppStorage("seerrURL")          private var seerrURL         = ""
    @AppStorage("seerrUsername")     private var seerrUsername    = ""
    @AppStorage("seerrPassword")     private var seerrPassword    = ""
    @AppStorage("seerrAuthMethod")   private var seerrAuthMethod  = JellyseerrAuthMethod.jellyfin
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
        .environment(authManager)
        .environment(mediaRepo)
        .environment(seerrRepo)
        .environment(statsRepo)
        .task { await authManager.checkStoredAuth() }
        .onAppear { configureSeerr() }
        .onChange(of: seerrURL)        { configureSeerr() }
        .onChange(of: seerrUsername)   { configureSeerr() }
        .onChange(of: seerrPassword)   { configureSeerr() }
        .onChange(of: seerrAuthMethod) { configureSeerr() }
        // Streamystats is reconfigured after load() sets serverID + we have the token
        .onChange(of: mediaRepo.serverID) { configureStats() }
        .onChange(of: statsURL)           { configureStats() }
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
