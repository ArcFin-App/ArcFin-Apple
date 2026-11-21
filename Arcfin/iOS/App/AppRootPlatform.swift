// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import SwiftData

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

    var playerCoversWindow: Bool { false }

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
        QuickActions.update(resumeItemID: nil, title: nil)
        WidgetSnapshotUpdater.clear()
        // The other device's Live Activity is only matched to the list when it comes back from
        // the server, which it won't now.
        AppServices.remoteSessions.stop()
        Task { await RemotePlaybackActivity.shared.sync() }
    }

    func refreshOnForeground(_ newPhase: ScenePhase, modelContext: ModelContext) {
        // NWPathMonitor's callback can be suspended along with the rest of the app while
        // backgrounded and doesn't reliably fire again the instant it resumes — coming
        // back to the foreground is exactly when the network is most likely to have
        // actually changed (left/rejoined home Wi-Fi, Wi-Fi toggled off entirely) without
        // Arcfin having noticed yet.
        // Leaving the app still counts as the foreground at .inactive, which a download
        // needs to start at full priority (see DownloadManager.handOffQueue).
        if newPhase == .inactive { downloadManager.handOffQueue() }
        if newPhase == .active {
            Task { await authManager.reresolveBaseURLIfNeeded() }
            downloadManager.refreshSmartDownloads()
            syncOfflineProgress(modelContext: modelContext)
        }
        // From here rather than the app delegate, which a scene-based app never tells about
        // going to the background or becoming active.
        if newPhase == .active {
            BackgroundRefresh.startWhileOpen()
        } else if !AppServices.scenes.anyActive {
            BackgroundRefresh.stopWhileOpen()
        }
        if newPhase == .background, !AppServices.scenes.anyForeground { BackgroundRefresh.schedule() }
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
