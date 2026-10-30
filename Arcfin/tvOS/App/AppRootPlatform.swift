// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

enum AppPhase: Equatable {
    case splash, login, main, offline
}

extension AppRootModel {
    func phase(offlineModeEnabled: Bool) -> AppPhase {
        guard splashDone else { return .splash }
        if offlineModeEnabled { return .offline }
        switch authManager.state {
        case .authenticated:   return .main
        case .unauthenticated: return .login
        }
    }

    var playerCoversWindow: Bool { false }

    /// No controls or Siri links on Apple TV.
    func handleRoutingLink(_ url: URL) {}

    func runPendingRoutes() {}
}

extension View {
    func appIntentRoutes(_ model: AppRootModel) -> some View {
        self
    }
}
