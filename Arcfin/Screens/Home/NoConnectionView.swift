// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

/// Replaces the whole tab bar/nav chrome — not just Home's content — when the server can't
/// be reached at all and there's nothing already loaded to fall back to showing. A half-drawn
/// tab bar and empty shelves look broken and leak the fact that content exists server-side to
/// anyone glancing at the screen; a single deliberate blank state reads as "offline," not "bug."
struct NoConnectionView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo

    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    @State private var showSwitchServer = false
    @State private var confirmSignOut = false

    private let tips = [
        "Check that Wi-Fi or Mobile Data is turned on",
        "Try turning Wi-Fi or Mobile Data off, then back on",
        "Quit Arcfin completely and reopen it",
        "Confirm your server is online and reachable from this network",
    ]

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 40)

                    Image(systemName: "wifi.slash")
                        .scaledFont(size: 44, weight: .medium)
                        .foregroundStyle(DT.Color.textSecondary)

                    VStack(spacing: 8) {
                        Text("Can't Reach Your Server")
                            .font(.system(.title2, design: .default, weight: .bold))
                            .foregroundStyle(DT.Color.textPrimary)
                        Text("Arcfin couldn't load anything from your Jellyfin server.")
                            .font(.system(.footnote))
                            .foregroundStyle(DT.Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(.caption2))
                                    .foregroundStyle(DT.Color.accent)
                                    .padding(.top, 6)
                                Text(tip)
                                    .font(.system(.footnote))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: 340, alignment: .leading)
                    .padding(16)
                    .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))

                    VStack(spacing: 12) {
                        Button {
                            retry()
                        } label: {
                            HStack(spacing: 8) {
                                if mediaRepo.isLoading { ProgressView().tint(.white) }
                                Text(mediaRepo.isLoading ? "Retrying…" : "Retry")
                            }
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: 340)
                            .frame(height: 48)
                            .background(DT.Color.accent, in: RoundedRectangle(cornerRadius: DT.Radius.md))
                        }
                        .disabled(mediaRepo.isLoading)

                        // Downloads/offline playback aren't wired up on macOS — see
                        // SettingsView/NotificationsSettingsView, which hide the same feature.
                        #if os(iOS)
                        Button {
                            offlineModeEnabled = true
                        } label: {
                            Text("Turn On Offline Mode")
                                .font(.system(.subheadline, design: .default, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .frame(maxWidth: 340)
                                .frame(height: 48)
                                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.md))
                        }
                        #endif

                        // A way out when the server is gone for good: another saved server,
                        // or back to sign-in.
                        #if !os(tvOS)
                        Button { showSwitchServer = true } label: {
                            Text("Switch Server")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(DT.Color.accent)
                                .frame(minHeight: 44)
                        }
                        #endif
                        Button("Sign Out", role: .destructive) { confirmSignOut = true }
                            .font(.system(.subheadline, weight: .semibold))
                            .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, 40)
            }
        }
        #if os(iOS)
        // This screen can replace the app while a landscape player was open.
        .onAppear { resetPlayerOrientation() }
        #endif
        #if !os(tvOS)
        .sheet(isPresented: $showSwitchServer) {
            NavigationStack { SwitchServerView() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #endif
        .confirmationDialog("Sign out of this server?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { authManager.signOut() }
        } message: {
            Text("You'll need to sign in again to use it. Downloads stay on this device.")
        }
    }

    private func retry() {
        guard case .authenticated(let credential) = authManager.state else { return }
        Task { await mediaRepo.load(credential: credential, authClient: authManager.authClient, force: true) }
    }
}

#Preview {
    NoConnectionView()
        .environment(AuthManager())
        .environment(MediaRepository())
}
