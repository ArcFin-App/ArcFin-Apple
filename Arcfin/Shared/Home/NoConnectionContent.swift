// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Replaces the whole tab bar/nav chrome — not just Home's content — when the server can't
/// be reached at all and there's nothing already loaded to fall back to showing. A half-drawn
/// tab bar and empty shelves look broken and leak the fact that content exists server-side to
/// anyone glancing at the screen; a single deliberate blank state reads as "offline," not "bug."
///
/// Each platform's `NoConnectionView` adds its own ways out between Retry and Sign Out.
struct NoConnectionContent<MoreActions: View>: View {
    let signOut: () -> Void
    @ViewBuilder let moreActions: MoreActions

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @State private var now = Date.now

    private let tips = [
        String(localized: "Check that Wi-Fi or Mobile Data is turned on"),
        String(localized: "Try turning Wi-Fi or Mobile Data off, then back on"),
        String(localized: "Quit Arcfin completely and reopen it"),
        String(localized: "Confirm your server is online and reachable from this network"),
    ]

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 40)

                    if let maintenance {
                        MaintenanceNotice(window: maintenance)
                    } else {
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
                    }

                    if maintenance == nil {
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
                    }

                    VStack(spacing: 12) {
                        Button {
                            retry()
                        } label: {
                            HStack(spacing: 8) {
                                if mediaRepo.isLoading { ProgressView().tint(DT.Color.onAccent) }
                                Text(mediaRepo.isLoading ? "Retrying…" : "Retry")
                            }
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(DT.Color.onAccent)
                            .frame(maxWidth: 340)
                            .frame(height: 48)
                            .background(DT.Color.accent, in: RoundedRectangle(cornerRadius: DT.Radius.md))
                        }
                        .buttonStyle(.plain)
                        .disabled(mediaRepo.isLoading || maintenance != nil)

                        moreActions

                        Button("Sign Out", role: .destructive) { signOut() }
                            .font(.system(.subheadline, weight: .semibold))
                            .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, 40)
            }
        }
        // During maintenance nothing is retried until the window ends; then once.
        .task(id: maintenance?.id) {
            guard let window = maintenance else { return }
            try? await Task.sleep(for: .seconds(max(1, window.ends.timeIntervalSinceNow + 5)))
            guard !Task.isCancelled else { return }
            now = .now
            retry()
        }
    }

    /// The admin's planned window the server is down for, from the notices kept on this device.
    private var maintenance: MaintenanceWindow? {
        ServerCompanion.shared.currentNotices()?.currentMaintenance(at: now)
    }

    private func retry() {
        guard case .authenticated(let credential) = authManager.state else { return }
        Task { await mediaRepo.load(credential: credential, authClient: authManager.authClient, force: true) }
    }
}
