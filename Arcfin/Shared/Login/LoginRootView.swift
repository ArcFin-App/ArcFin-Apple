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
    @State private var setupHost = AppleTVSetupHost()

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
        .task {
            if PlatformMetrics.hostsAppleTVSetup { setupHost.start(authManager: authManager) }
        }
        .onDisappear { setupHost.stop() }
        .appSheet(isPresented: Binding(get: { setupHost.phase != .idle },
                                       set: { if !$0 { setupHost.cancelSession() } })) {
            AppleTVSetupHostView(host: setupHost)
        }
        // Quick Connect is off on the server the phone sent: its password page.
        .onChange(of: setupHost.passwordServer) { _, url in
            guard let url else { return }
            setupHost.passwordServer = nil
            withAnimation(DT.Animation.standard) {
                step = .auth(serverURL: url, serverName: url.host() ?? url.absoluteString)
            }
        }
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
