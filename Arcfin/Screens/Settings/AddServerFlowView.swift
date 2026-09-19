import SwiftUI
import AuthCore

private enum AddServerStep {
    case serverURL
    case auth(serverURL: URL, serverName: String)
}

/// Same two-step flow as the initial sign-in (LoginRootView) — server URL, then
/// credentials — but wired to add a new profile alongside existing ones instead of
/// replacing the current session. Mirrors tvOS's TVAddProfileFlowView.
struct AddServerFlowView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var step: AddServerStep = .serverURL

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

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
                AuthView(serverURL: url, serverName: name, onBack: {
                    withAnimation(DT.Animation.standard) { step = .serverURL }
                }, onAuthenticated: { credential in
                    authManager.addProfile(credential)
                    dismiss()
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(DT.Animation.standard, value: stepTag)
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var stepTag: Int {
        switch step {
        case .serverURL: return 0
        case .auth: return 1
        }
    }
}
