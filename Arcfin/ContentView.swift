import SwiftUI
import AuthCore

private enum AppPhase: Equatable {
    case splash, login, main
}

struct ContentView: View {
    @State private var authManager = AuthManager()
    @State private var splashDone = false

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
        .task { await authManager.checkStoredAuth() }
    }
}

#Preview {
    ContentView()
}
