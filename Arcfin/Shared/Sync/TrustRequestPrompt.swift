// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

extension View {
    /// On a trusted device: asks about another of the person's devices waiting to be trusted,
    /// checking every minute while the app is in front.
    func trustRequestPrompt() -> some View {
        modifier(TrustRequestPrompt())
    }
}

private struct TrustRequestPrompt: ViewModifier {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.scenePhase) private var scenePhase

    private var companion: ServerCompanion { .shared }

    func body(content: Content) -> some View {
        content
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await companion.refreshTrustRequests(authManager: authManager)
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .alert(companion.trustRequest.map { String(localized: "Trust \($0.deviceName)?") } ?? "",
                   isPresented: Binding(get: { companion.trustRequest != nil }, set: { _ in })) {
                Button("Trust") { Task { await companion.answerTrust(true, authManager: authManager) } }
                Button("Don't Trust", role: .destructive) { Task { await companion.answerTrust(false, authManager: authManager) } }
            } message: {
                Text(companion.trustRequest.map { String(localized: "Only trust it if it shows code \($0.code).") } ?? "")
            }
    }
}
