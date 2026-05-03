import SwiftUI

private enum AppPhase {
    case splash, login, main
}

struct ContentView: View {
    @State private var phase: AppPhase = .splash

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView {
                    withAnimation(DT.Animation.standard) { phase = .login }
                }
                .transition(.opacity)

            case .login:
                LoginRootView {
                    withAnimation(DT.Animation.standard) { phase = .main }
                }
                .transition(.opacity)

            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(DT.Animation.standard, value: phase == .main)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
