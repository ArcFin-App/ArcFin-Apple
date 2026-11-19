// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = AppRootModel()
    @AppStorage("appLockUseFaceID") private var appLockUseFaceID = true
    @State private var showOfflineDocPicker = false
    @State private var offlinePickedURL: URL?
    @State private var navigateToOfflineLocalPlayer = false
    @State private var bypassSessionCheck = false
    @State private var showOfflineMusic = false

    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false

    private var phase: AppPhase {
        model.phase(offlineModeEnabled: offlineModeEnabled, bypassSessionCheck: bypassSessionCheck)
    }

    // Extracted out of body — one giant ZStack combining this switch, the overlay ifs
    // below, and body's own long modifier chain made the whole expression too much for
    // the type checker to resolve in reasonable time. Splitting it into its own
    // @ViewBuilder gives the compiler a much smaller expression to solve on its own.
    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .splash:
            SplashView(isLoading: model.authManager.isChecking) { model.splashDone = true }
                .transition(.opacity)
        case .login:
            LoginRootView()
                .transition(.opacity)
        case .checkingSession:
            SessionCheckingView(
                onSignInManually: { bypassSessionCheck = true },
                onGoOffline: { offlineModeEnabled = true }
            )
            .transition(.opacity)
        case .main:
            // The profile's access schedule, checked every minute.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                // context.date only drives the minute-by-minute check; the time compared is
                // the trusted one.
                if context.date > .distantPast, ProfileRules.shared.isWithinSchedule() {
                    MainTabView()
                } else {
                    AccessScheduleView(onSwitchProfile: { model.switchProfileFromSchedule() })
                }
            }
            .transition(.opacity)
        case .offline:
            NavigationStack {
                DownloadsView(goBackOnline: { offlineModeEnabled = false })
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button { showOfflineDocPicker = true } label: {
                                Image(systemName: "folder")
                            }
                            .accessibilityLabel("Open local file")
                            .help("Open a video file")
                        }
                        // Saved songs play without the server too.
                        if !MusicDownloads.shared.isEmpty {
                            ToolbarItem(placement: .navigation) {
                                Button { showOfflineMusic = true } label: {
                                    Image(systemName: "music.note")
                                }
                                .accessibilityLabel("Downloaded Music")
                                .help("Downloaded Music")
                            }
                        }
                    }
                    .navigationDestination(isPresented: $showOfflineMusic) { MusicDownloadsView() }
                    .fileImporter(isPresented: $showOfflineDocPicker, allowedContentTypes: UTType.playableVideo) { result in
                        guard case .success(let url) = result else { return }
                        offlinePickedURL = url
                        navigateToOfflineLocalPlayer = true
                    }
                    .navigationDestination(isPresented: $navigateToOfflineLocalPlayer) {
                        if let url = offlinePickedURL { LocalPlayerView(url: url) }
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if AppServices.music.isActive { MusicPlayerBar() }
            }
            .transition(.opacity)
        }
    }

    var body: some View {
        ZStack {
            phaseContent
                // Title pages pin their content to the container's width. Sized from that
                // content, the window grew by the sidebar's width on every pass until AppKit
                // aborted (#345). With both bounds set the frame takes the window's size and
                // never asks the content for one.
                .frame(minWidth: 800, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)

            if model.isShowing(.onboarding, phase: phase) {
                OnboardingView(isSignedIn: phase == .main) { model.introduction.finishOnboarding() }
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                    .zIndex(5)
            }

            if model.isAppLocked {
                AppLockView(useFaceID: appLockUseFaceID) { model.unlock() }
                    .transition(.opacity)
                    .zIndex(10)
            }

            // A .sheet on macOS is an inherently small, modal, parent-attached panel — it
            // can't properly fill or fullscreen a window, which is exactly why the player
            // looked stuck small with a non-functional fullscreen button. This mirrors
            // AppLockView's own full-window overlay pattern instead: real window-filling
            // content, and a real working NSWindow-level fullscreen. iOS/tvOS are untouched
            // and keep using their existing per-screen .fullScreenCover.
            if let request = model.playbackPresenter.request {
                PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                    model.playbackPresenter.present(next, onPlayNext: request.onPlayNext)
                }
                // A new request (the next episode) needs a new player: the same view would keep
                // the finished episode's state and never set up the new one.
                .id(request.id)
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(DT.Animation.standard, value: phase)
        .animation(DT.Animation.standard, value: model.isAppLocked)
        .animation(DT.Animation.standard, value: model.introduction.presentation)
        .sheet(isPresented: model.introductionBinding(.whatsNew, phase: phase)) {
            WhatsNewView { model.introduction.finishWhatsNew() }
                .frame(width: 520, height: 620)
        }
        .modifier(AppRootLifecycle(model: model))
    }
}

#Preview {
    ContentView()
}
