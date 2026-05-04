import SwiftUI
import AuthCore

private enum AppPhase: Equatable {
    case splash, login, main
}

struct ContentView: View {
    @State private var authManager = AuthManager()
    @State private var mediaRepo = MediaRepository()
    @State private var seerrRepo = JellyseerrRepository()
    @State private var splashDone = false

    @AppStorage("seerrURL")    private var seerrURL    = ""
    @AppStorage("seerrAPIKey") private var seerrAPIKey = ""

    private var phase: AppPhase {
        guard splashDone && !authManager.isChecking else { return .splash }
        switch authManager.state {
        case .authenticated: return .main
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
        .task { await authManager.checkStoredAuth() }
        .onAppear { seerrRepo.configure(urlString: seerrURL, apiKey: seerrAPIKey) }
        .onChange(of: seerrURL)    { seerrRepo.configure(urlString: seerrURL, apiKey: seerrAPIKey) }
        .onChange(of: seerrAPIKey) { seerrRepo.configure(urlString: seerrURL, apiKey: seerrAPIKey) }
    }
}

#Preview {
    ContentView()
}
