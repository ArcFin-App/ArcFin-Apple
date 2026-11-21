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
    @State private var sceneID = UUID()
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
            // A link to arcfin.psmattas.com that opens the app (the Apple TV's QR code) comes as
            // a browsing activity, not through onOpenURL.
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { model.handleDeepLink(url) }
            }
            .appIntentRoutes(model)
            .smartDownloadsIgnorePrompt(model.downloadManager)
            .task { await model.checkLaunch() }
            .task { model.authManager.startNetworkMonitoring() }
            .task {
                model.sharePlayManager.currentServerId = { [mediaRepo = model.mediaRepo] in mediaRepo.serverID }
                await model.sharePlayManager.observeSessions()
            }
            .task {
                MusicSharePlay.shared.currentServerId = { [mediaRepo = model.mediaRepo] in mediaRepo.serverID }
                await MusicSharePlay.shared.observeSessions()
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
                AppServices.scenes.set(newPhase, for: sceneID)
                model.scenePhaseChanged(to: newPhase)
                onScenePhase(newPhase)
                // Deliberately no re-lock here. scenePhase drops to .background not just when
                // the app is actually left, but also pulling down Notification/Control Center
                // over it and entering Picture in Picture (the app's own UI is off-screen, so
                // the system backgrounds the scene) — locking on every one of those made the
                // PIN/Face ID prompt reappear on nearly every interaction. The PIN/Face ID
                // gate now only ever applies at cold launch (see the initial .task above).
                // Music still to download goes to the system, which carries on with it.
                if newPhase == .background { MusicDownloads.shared.handOff() }
            }
            .onChange(of: model.authManager.state) { _, _ in Task { await model.refreshLockRequirement() } }
            .onAppear {
                AppServices.scenes.set(scenePhase, for: sceneID)
                configureSeerr()
            }
            .onChange(of: seerrURL)        { configureSeerr() }
            .onChange(of: seerrUsername)   { configureSeerr() }
            .onChange(of: model.authManager.seerrPassword) { configureSeerr() }
            .onChange(of: seerrAuthMethod) { configureSeerr() }
            // A profile switch keeps the same Seerr URL/username/password today, so
            // configureSeerr() above would just no-op as "nothing changed" — this instead clears
            // any stuck auth-failure cooldown and retries directly (see
            // SeerrRepository.retryAfterProfileSwitch).
            .onChange(of: model.authManager.state.credential?.id) {
                // The profile's own TMDB key and Seerr; configureSeerr follows from the URL and
                // username observers once the new profile's values are in place.
                model.seerrRepo.reloadTMDB()
                configureSeerr()
                Task { await model.seerrRepo.retryAfterProfileSwitch() }
            }
            .onChange(of: model.authManager.profiles.isEmpty) { _, isEmpty in
                if isEmpty { model.seerrRepo.reloadTMDB() }
            }
            .onChange(of: model.authManager.state) { oldState, newState in
                if case .authenticated = newState {
                    model.syncOfflineProgress(modelContext: modelContext)
                } else if oldState.credential != nil {
                    model.forgetSignedOutAccount()
                }
            }
            // The explicit "I'm back online" moment — items played while offline sync then too,
            // not just at next cold launch.
            .onChange(of: model.authManager.networkChanges) {
                model.syncOfflineProgress(modelContext: modelContext)
                // Back online: catch downloads up on what was watched elsewhere meanwhile.
                model.downloadManager.refreshSmartDownloads()
            }
            // The profile's parental controls and permissions, from the server: on sign-in, a
            // profile switch, and on returning to the app (an admin may have changed them; see
            // scenePhaseChanged).
            .task(id: model.authManager.state.credential?.id) { await model.loadProfileRules() }
            .task(id: LiveUpdatesKey(credentialID: model.authManager.state.credential?.id,
                                     isActive: AppServices.scenes.anyForeground || PlayerActivity.shared.isPlayerOpen)) {
                if AppServices.scenes.anyForeground || PlayerActivity.shared.isPlayerOpen,
                   let credential = model.authManager.state.credential {
                    AppServices.liveUpdates.connect(credential: credential, authClient: model.authManager.authClient)
                } else {
                    AppServices.liveUpdates.disconnect()
                }
            }
            .modifier(AppRootPrompts(model: model, sceneID: sceneID))
            .onChange(of: offlineModeEnabled) { _, isOffline in
                if !isOffline { model.syncOfflineProgress(modelContext: modelContext) }
            }
            // Once a sync has brought the server's Seerr address, connect Seerr with the Jellyfin
            // account if this profile hasn't yet (see checkSeerrSetupPrompt).
            .onChange(of: model.authManager.isSyncingArcfin) { _, isSyncing in
                if !isSyncing {
                    model.checkSeerrSetupPrompt(seerrURL: seerrURL, seerrUsername: seerrUsername, seerrAuthMethod: seerrAuthMethod)
                }
            }
            .appSheet(isPresented: Bindable(model).showSeerrSetupPrompt) {
                if case .authenticated(let cred) = model.authManager.state {
                    SeerrSetupPromptView(
                        seerrURL: seerrURL,
                        jellyfinUsername: cred.displayName,
                        authorizeQuickConnect: SeerrSignIn.quickConnectAuthorizer(authManager: model.authManager),
                        initialError: model.seerrSetupError,
                        onConnected: { username, password in
                            seerrUsername = username
                            if password.isEmpty {
                                model.authManager.removeSeerrPassword()
                            } else {
                                model.authManager.saveSeerrPassword(password)
                            }
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

/// What can pop up over any screen: a scanned Apple TV code, an Apple TV to set up, and a
/// message from the server's dashboard. Kept apart from AppRootLifecycle, whose chain of
/// modifiers was getting too long to type-check.
private struct AppRootPrompts: ViewModifier {
    let model: AppRootModel
    let sceneID: UUID
    private var setupGuide: NearbySetupGuide { AppServices.nearbySetup }

    /// Prompts that act for the signed-in profile wait for the launch checks and the PIN lock.
    private var canPrompt: Bool { model.splashDone && model.launchChecked && !model.isAppLocked }

    /// Looks for an Apple TV to set up only while it could be offered: signed in, in front,
    /// unlocked and not watching something.
    private var offersNearbySetup: Bool {
        PlatformMetrics.setsUpNearbyDevices && canPrompt && AppServices.scenes.anyActive
            && model.authManager.state.credential != nil && !PlayerActivity.shared.isPlayerOpen
    }

    /// Not while this device's own player covers the screen the remote bar sits on.
    private var watchesOtherDevices: Bool {
        PlatformMetrics.controlsOtherDevices && canPrompt && AppServices.scenes.anyActive
            && model.authManager.state.credential != nil
            && (!PlayerActivity.shared.isPlayerOpen || AppServices.remoteSessions.isShowingRemote)
    }

    func body(content: Content) -> some View {
        content
        .onDisappear { AppServices.scenes.remove(sceneID) }
        // A scanned Quick Connect code: nothing is signed in until it's confirmed here.
        .alert("Sign In Apple TV?",
               isPresented: Binding(get: { QuickConnectApproval.shared.request != nil && canPrompt },
                                    set: { if !$0 { QuickConnectApproval.shared.request = nil } }),
               presenting: QuickConnectApproval.shared.request) { request in
            Button("Sign In") { QuickConnectApproval.shared.approve(request, authManager: model.authManager) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            if let name = model.authManager.state.credential?.displayName {
                Text("The Apple TV showing this code signs in to your server as \(name).")
            } else {
                Text("Sign in to Arcfin on this device first.")
            }
        }
        .alert(QuickConnectApproval.shared.outcome?.succeeded == true ? Text("Apple TV Signed In") : Text("Couldn't Sign In Apple TV"),
               isPresented: Binding(get: { QuickConnectApproval.shared.outcome != nil },
                                    set: { if !$0 { QuickConnectApproval.shared.outcome = nil } }),
               presenting: QuickConnectApproval.shared.outcome) { _ in
            Button("OK") {}
        } message: { outcome in
            Text(outcome.message)
        }
        // Other devices playing on this profile, for the remote (#457).
        .task(id: watchesOtherDevices) {
            if watchesOtherDevices {
                AppServices.remoteSessions.start(authManager: model.authManager)
            } else {
                AppServices.remoteSessions.stop()
            }
        }
        // A signed-out Apple TV on the network, offered for setup with this profile (#481).
        .task(id: offersNearbySetup) {
            if offersNearbySetup { setupGuide.start(authManager: model.authManager) } else { setupGuide.stop() }
        }
        .sheet(isPresented: Binding(get: { setupGuide.phase != .idle && canPrompt },
                                    set: { if !$0 { setupGuide.notNow() } })) {
            NearbySetupCard(guide: setupGuide, authManager: model.authManager)
                    .environment(model.authManager)
        }
        // A message from the dashboard while nothing is playing; the player shows its own.
        .alert(Text(verbatim: RemoteControl.shared.message.flatMap { $0.header.isEmpty ? nil : $0.header } ?? "Arcfin"),
               isPresented: Binding(get: { RemoteControl.shared.message != nil },
                                    set: { if !$0 { RemoteControl.shared.message = nil } }),
               presenting: RemoteControl.shared.message) { _ in
            Button("OK") {}
        } message: { message in
            Text(verbatim: message.text)
        }
    }
}
