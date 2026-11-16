// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

private enum AddServerStep {
    case serverURL
    case auth(serverURL: URL, serverName: String)
}

/// Same two-step flow as the initial sign-in (LoginRootView) — server URL, then
/// credentials — but wired to add a new profile alongside existing ones instead of
/// replacing the current session. Mirrors tvOS's TVAddProfileFlowView. Each platform's
/// AddServerFlowView shows it.
struct AddServerSteps: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var step: AddServerStep = .serverURL
    @State private var setupHost = AppleTVSetupHost()

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            switch step {
            case .serverURL:
                ServerURLView(onConnected: { url, name in
                    withAnimation(DT.Animation.standard) {
                        step = .auth(serverURL: url, serverName: name)
                    }
                }, onBack: { dismiss() })
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
        // Apple TV: another profile can be added from Arcfin on an iPhone or iPad too (#481).
        .task {
            if PlatformMetrics.hostsAppleTVSetup { setupHost.start(authManager: authManager) }
        }
        .onDisappear { setupHost.stop() }
        .appSheet(isPresented: Binding(get: { setupHost.phase != .idle },
                                       set: { if !$0 { setupHost.cancelSession() } })) {
            AppleTVSetupHostView(host: setupHost)
        }
        .onChange(of: setupHost.completedSetups) { dismiss() }
        .onChange(of: setupHost.passwordServer) { _, url in
            guard let url else { return }
            setupHost.passwordServer = nil
            withAnimation(DT.Animation.standard) {
                step = .auth(serverURL: url, serverName: url.host() ?? url.absoluteString)
            }
        }
    }

    private var stepTag: Int {
        switch step {
        case .serverURL: return 0
        case .auth: return 1
        }
    }
}
