// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Server-wide active sessions (GET /Sessions) — admin-only, linked from SettingsView only
/// when authManager.isAdmin. Self-hosters running Arcfin are very often also the server
/// admin, so "who else is streaming right now" is a genuinely useful thing to see without
/// leaving the app for the Jellyfin web dashboard.
struct AdminSessionsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var sessions: [JellyfinSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var refreshTask: Task<Void, Never>?

    private let client = JellyfinMediaClient()

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            } else if sessions.isEmpty && !isLoading {
                Section {
                    Text("No active sessions.")
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Active Sessions")
        .task { await load() }
        .refreshable { await load() }
        .onAppear { startAutoRefresh() }
        .onDisappear { refreshTask?.cancel() }
    }

    private func sessionRow(_ session: JellyfinSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.userName ?? "Unknown User")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("\(session.deviceName) · \(session.clientName)")
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                if session.nowPlayingItemName != nil {
                    Image(systemName: session.isPaused ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(.title3))
                        .foregroundStyle(session.isPaused ? DT.Color.textSecondary : DT.Color.accent)
                }
            }

            if let title = session.nowPlayingItemName {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.footnote, design: .default, weight: .medium))
                        .foregroundStyle(DT.Color.textPrimary)
                    if let position = session.positionTicks, let duration = session.runTimeTicks, duration > 0 {
                        ProgressView(value: Double(position), total: Double(duration))
                            .tint(DT.Color.accent)
                        HStack {
                            Text(timeLabel(position))
                            Spacer()
                            Text(timeLabel(duration))
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .padding(.top, 2)
            } else if let lastActivity = session.lastActivityDate {
                Text("Idle · last active \(lastActivity.formatted(.relative(presentation: .named)))")
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeLabel(_ ticks: Int64) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func load() async {
        guard case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        do {
            sessions = try await client.getActiveSessions(credential: credential, authHeader: authHeader)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load active sessions."
        }
        isLoading = false
    }

    /// Sessions are live state — a static snapshot goes stale the moment someone else
    /// starts/stops playing, so this screen refreshes itself while it's on screen.
    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }
}

#Preview {
    NavigationStack { AdminSessionsView() }
        .environment(AuthManager())
}
