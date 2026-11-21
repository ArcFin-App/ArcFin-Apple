// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

enum AppPhase: Equatable {
    case splash, login, main, offline
    // SplashView always exits after its own fixed minimum presentation time regardless of
    // whether checkStoredAuth() has concluded, so a slow network previously meant the app
    // dropped straight to the Login screen while an already-valid session was still being
    // confirmed in the background.
    case checkingSession
}

extension AppRootModel {
    func phase(offlineModeEnabled: Bool, bypassSessionCheck: Bool) -> AppPhase {
        guard splashDone else { return .splash }
        if offlineModeEnabled { return .offline }
        if !bypassSessionCheck, authManager.isChecking, authManager.state == .unauthenticated {
            return .checkingSession
        }
        switch authManager.state {
        case .authenticated:   return .main
        case .unauthenticated: return .login
        }
    }

    /// The player covers the main window; the tour and What's New wait for it to close.
    var playerCoversWindow: Bool { playbackPresenter.request != nil }

    /// arcfin://discover and arcfin://search, from a control or Siri.
    func handleRoutingLink(_ url: URL) {
        switch url.host {
        case "discover":
            ArcfinRouting.showDiscover()
        case "search":
            ArcfinRouting.search(url.pathComponents.dropFirst().first ?? "")
        default:
            break
        }
    }

    func consumeControlLink() {
        guard let link = UserDefaults.standard.string(forKey: ControlRoute.pendingKey), let url = URL(string: link) else { return }
        UserDefaults.standard.removeObject(forKey: ControlRoute.pendingKey)
        handleDeepLink(url)
    }

    /// A control's or Siri's link that arrived before the launch checks finished.
    func runPendingRoutes() {
        consumeControlLink()
        startPendingDownload()
    }

    /// Signed out, or the sign-in expired: nothing outside the app keeps offering the last
    /// account's titles, and a title tapped before this doesn't open for whoever signs in next.
    func forgetSignedOutAccount() {
        UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
        WidgetSnapshotUpdater.clear()
    }
}

extension View {
    /// A control's link and Siri's Download Next Episode while the app is open.
    func appIntentRoutes(_ model: AppRootModel) -> some View {
        onReceive(NotificationCenter.default.publisher(for: ControlRoute.notification)) { _ in
            model.consumeControlLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: DownloadRoute.notification)) { _ in
            model.startPendingDownload()
        }
    }
}
