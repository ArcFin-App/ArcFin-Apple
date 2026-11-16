// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

private enum LoginStep {
    case serverURL
    case auth(serverURL: URL, serverName: String)
}

struct LoginRootView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var step: LoginStep?

    private var currentStep: LoginStep {
        if let step { return step }
        guard let expired = authManager.expiredCredential else { return .serverURL }
        return .auth(serverURL: expired.baseURL, serverName: expired.baseURL.host() ?? expired.baseURL.absoluteString)
    }

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            switch currentStep {
            case .serverURL:
                ServerURLView(onConnected: { url, name in
                    withAnimation(DT.Animation.standard) {
                        step = .auth(serverURL: url, serverName: name)
                    }
                })
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
        .hostsAppleTVSetup(onPasswordServer: { url in
            withAnimation(DT.Animation.standard) {
                step = .auth(serverURL: url, serverName: url.host() ?? url.absoluteString)
            }
        })
    }

    private var stepTag: Int {
        switch currentStep {
        case .serverURL: return 0
        case .auth: return 1
        }
    }
}

#Preview {
    LoginRootView()
        .environment(AuthManager())
}
