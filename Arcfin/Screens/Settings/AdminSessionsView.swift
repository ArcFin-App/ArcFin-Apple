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
    @State private var socket: JellyfinWebSocketClient?
    @State private var socketTask: Task<Void, Never>?
    @State private var receivedAt = Date()
    @State private var lastPush: Date?

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
        .onAppear {
            startLiveUpdates()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
            stopLiveUpdates()
        }
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
                        // Clients only report progress every few seconds; advance the clock
                        // locally in between so a playing row doesn't stall and jump.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = session.isPaused ? 0 : Int64(context.date.timeIntervalSince(receivedAt) * 10_000_000)
                            let current = min(position + max(elapsed, 0), duration)
                            VStack(spacing: 4) {
                                ProgressView(value: Double(current), total: Double(duration))
                                    .tint(DT.Color.accent)
                                HStack {
                                    Text(timeLabel(current))
                                    Spacer()
                                    Text(timeLabel(duration))
                                }
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
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
            apply(try await client.getActiveSessions(credential: credential, authHeader: authHeader))
        } catch {
            errorMessage = "Couldn't load active sessions."
        }
        isLoading = false
    }

    private func apply(_ newSessions: [JellyfinSession]) {
        sessions = newSessions
        receivedAt = Date()
        errorMessage = nil
        isLoading = false
    }

    private func startLiveUpdates() {
        stopLiveUpdates()
        guard case .authenticated(let credential) = authManager.state else { return }
        let deviceId = UserDefaults.standard.string(forKey: "arcfin.deviceId") ?? UUID().uuidString
        let socket = JellyfinWebSocketClient(credential: credential, deviceId: deviceId)
        self.socket = socket
        socket.startSessionUpdates()
        socketTask = Task {
            for await event in socket.events {
                guard case .sessions(let pushed) = event else { continue }
                lastPush = Date()
                apply(pushed)
            }
        }
    }

    private func stopLiveUpdates() {
        socketTask?.cancel()
        socket?.stopSessionUpdates()
        socket?.close()
        socket = nil
    }

    /// Fallback for when the WebSocket can't connect (e.g. a reverse proxy that doesn't
    /// forward upgrades) — polls only while no push has arrived recently.
    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if let lastPush, Date().timeIntervalSince(lastPush) < 5 { continue }
                await load()
            }
        }
    }
}

#Preview {
    NavigationStack { AdminSessionsView() }
        .environment(AuthManager())
}
