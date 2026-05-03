import SwiftUI
import AuthCore

private enum LoginStep {
    case serverURL
    case auth(serverURL: URL, serverName: String)
}

struct LoginRootView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var step: LoginStep = .serverURL

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            VStack {
                RadialGradient(
                    colors: [DT.Color.accent.opacity(0.07), .clear],
                    center: .center, startRadius: 0, endRadius: 200
                )
                .frame(height: 300)
                .blur(radius: 40)
                Spacer()
            }
            .ignoresSafeArea()

            switch step {
            case .serverURL:
                ServerURLView { url, name in
                    withAnimation(DT.Animation.standard) {
                        step = .auth(serverURL: url, serverName: name)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            case .auth(let url, let name):
                AuthView(serverURL: url, serverName: name) {
                    withAnimation(DT.Animation.standard) { step = .serverURL }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(DT.Animation.standard, value: stepTag)
    }

    private var stepTag: Int {
        switch step {
        case .serverURL: return 0
        case .auth: return 1
        }
    }
}

#Preview {
    LoginRootView()
        .environment(AuthManager())
}
