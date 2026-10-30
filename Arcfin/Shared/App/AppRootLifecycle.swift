// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import SwiftData
import SeerrAPI

/// Everything each platform's `ContentView` does around its screens: the app's environment,
/// deep links, the launch checks, the work when the app becomes active, Seerr set-up and
/// SharePlay notices. `onScenePhase` is the platform's own part of the scene phase change.
struct AppRootLifecycle: ViewModifier {
    let model: AppRootModel
    let onScenePhase: (ScenePhase) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage("seerrURL")          private var seerrURL         = ""
    @AppStorage("seerrUsername")     private var seerrUsername    = ""
    @AppStorage("seerrAuthMethod")   private var seerrAuthMethod  = SeerrAuthMethod.jellyfin
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false

    init(model: AppRootModel, onScenePhase: @escaping (ScenePhase) -> Void = { _ in }) {
        self.model = model
        self.onScenePhase = onScenePhase
    }

    func body(content: Content) -> some View {
        content
            .environment(model.authManager)
            .environment(model.mediaRepo)
            .environment(model.playbackPresenter)
            .environment(model.seerrRepo)
            .environment(model.downloadManager)
            .environment(model.syncPlayManager)
            .environment(model.sharePlayManager)
            .onOpenURL { model.handleDeepLink($0) }
            .appIntentRoutes(model)
            .task { await model.checkLaunch() }
            .task { model.authManager.startNetworkMonitoring() }
            .task {
                model.sharePlayManager.currentServerId = { [mediaRepo = model.mediaRepo] in mediaRepo.serverID }
                await model.sharePlayManager.observeSessions()
            }
            // With a player open, it shows these itself.
            .alert("SharePlay", isPresented: Binding(
                get: { model.sharePlayManager.notice != nil && !model.sharePlayManager.hasOpenPlayer },
                set: { if !$0 { model.sharePlayManager.notice = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.sharePlayManager.notice ?? "")
            }
            .task { model.seerrRepo.reloadTMDB() }
            .onChange(of: model.mediaRepo.connectionFailed) { _, failed in
                if failed { Task { await model.authManager.checkSignInStillValid() } }
            }
            .task { model.downloadManager.configure(modelContext: modelContext, authManager: model.authManager) }
            .onChange(of: scenePhase) { _, newPhase in
                model.scenePhaseChanged(to: newPhase)
                onScenePhase(newPhase)
                // Deliberately no re-lock here. scenePhase drops to .background not just when
                // the app is actually left, but also pulling down Notification/Control Center
                // over it and entering Picture in Picture (the app's own UI is off-screen, so
                // the system backgrounds the scene) — locking on every one of those made the
                // PIN/Face ID prompt reappear on nearly every interaction. The PIN/Face ID
                // gate now only ever applies at cold launch (see the initial .task above).
                if newPhase == .active {
                    Task { await model.loadProfileRules() }
                }
            }
            .onChange(of: model.authManager.state) { _, _ in Task { await model.refreshLockRequirement() } }
            .onAppear { configureSeerr() }
            .onChange(of: seerrURL)        { configureSeerr() }
            .onChange(of: seerrUsername)   { configureSeerr() }
            .onChange(of: model.authManager.seerrPassword) { configureSeerr() }
            .onChange(of: seerrAuthMethod) { configureSeerr() }
            // A profile switch keeps the same Seerr URL/username/password today, so
            // configureSeerr() above would just no-op as "nothing changed" — this instead clears
            // any stuck auth-failure cooldown and retries directly (see
            // SeerrRepository.retryAfterProfileSwitch).
            .onChange(of: model.authManager.state) { Task { await model.seerrRepo.retryAfterProfileSwitch() } }
            .onChange(of: model.authManager.profiles.isEmpty) { _, isEmpty in
                if isEmpty { model.seerrRepo.reloadTMDB() }
            }
            .onChange(of: model.authManager.state) { _, newState in
                if case .authenticated = newState { model.syncOfflineProgress(modelContext: modelContext) }
            }
            // The explicit "I'm back online" moment — items played while offline sync then too,
            // not just at next cold launch.
            .onChange(of: model.authManager.networkChanges) {
                model.syncOfflineProgress(modelContext: modelContext)
                // Back online: catch downloads up on what was watched elsewhere meanwhile.
                model.downloadManager.refreshSmartDownloads()
            }
            // The profile's parental controls and permissions, from the server: on sign-in, a
            // profile switch, and each return to the app (an admin may have changed them).
            .task(id: model.authManager.state.credential?.id) { await model.loadProfileRules() }
            .task(id: LiveUpdatesKey(credentialID: model.authManager.state.credential?.id, isActive: scenePhase == .active)) {
                if scenePhase == .active, let credential = model.authManager.state.credential {
                    AppServices.liveUpdates.connect(credential: credential, authClient: model.authManager.authClient)
                } else {
                    AppServices.liveUpdates.disconnect()
                }
            }
            .onChange(of: offlineModeEnabled) { _, isOffline in
                if !isOffline { model.syncOfflineProgress(modelContext: modelContext) }
            }
            // Quick Connect sign-in has no password to auto-fill Seerr with (see AuthView's
            // attemptSeerrAutoLogin, which only runs on the password-based path) — once a sync
            // confirms Seerr is locked to a Jellyfin account server-side but this profile still
            // has no Seerr credential, offer to connect it interactively instead of leaving it
            // silently broken with no way to fix it (Settings hides the fields while locked).
            .onChange(of: model.authManager.isSyncingArcfin) { _, isSyncing in
                if !isSyncing {
                    model.checkSeerrSetupPrompt(seerrURL: seerrURL, seerrUsername: seerrUsername, seerrAuthMethod: seerrAuthMethod)
                }
            }
            .sheet(isPresented: Bindable(model).showSeerrSetupPrompt) {
                if case .authenticated(let cred) = model.authManager.state {
                    SeerrSetupPromptView(
                        seerrURL: seerrURL,
                        jellyfinUsername: cred.displayName,
                        onConnected: { username, password in
                            seerrUsername = username
                            model.authManager.saveSeerrPassword(password)
                            model.markSeerrSetupPromptHandled(for: cred.id)
                        },
                        onDismiss: { model.markSeerrSetupPromptHandled(for: cred.id) }
                    )
                }
            }
    }

    private func configureSeerr() {
        model.configureSeerr(seerrURL: seerrURL, seerrUsername: seerrUsername, seerrAuthMethod: seerrAuthMethod)
    }
}
