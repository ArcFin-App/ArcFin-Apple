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
    @State private var messageTarget: JellyfinSession?
    @State private var messageText = ""
    @State private var actionError: String?

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
                        .contextMenu { if session.supportsRemoteControl { sessionActions(session) } }
                        #if !os(tvOS)
                        .swipeActions {
                            if session.supportsRemoteControl, session.nowPlayingItemName != nil {
                                Button(session.isPaused ? "Resume" : "Pause",
                                       systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                                    send(session.isPaused ? .unpause : .pause, to: session)
                                }
                                .tint(DT.Color.accent)
                            }
                        }
                        #endif
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Active Sessions")
        .task { await load() }
        .refreshable { await load() }
        .alert("Send a Message", isPresented: Binding(get: { messageTarget != nil }, set: { if !$0 { messageTarget = nil } })) {
            TextField("Message", text: $messageText)
            Button("Send") {
                if let messageTarget { sendMessage(messageText, to: messageTarget) }
                messageText = ""
            }
            Button("Cancel", role: .cancel) { messageText = "" }
        } message: {
            Text("Shows on \(messageTarget?.deviceName ?? "the device") for 15 seconds.")
        }
        .alert("Couldn't Reach That Session", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
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
                if let method = playbackMethodText(session) {
                    Text(method)
                        .font(.system(.caption2))
                        .foregroundStyle(session.playMethod == "Transcode" ? DT.Color.palette("f59e0b") : DT.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let lastActivity = session.lastActivityDate {
                Text("Idle · last active \(lastActivity.formatted(.relative(presentation: .named)))")
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sessionActions(_ session: JellyfinSession) -> some View {
        if session.nowPlayingItemName != nil {
            Button(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                send(session.isPaused ? .unpause : .pause, to: session)
            }
            Button("Stop Playback", systemImage: "stop.fill", role: .destructive) { send(.stop, to: session) }
        }
        Button("Send Message…", systemImage: "text.bubble") { messageTarget = session }
    }

    /// "Direct Play", or for a transcode what's being converted, at what rate, and the
    /// server's reasons, which is what an admin needs to fix it (a codec setting, a bitrate limit).
    private func playbackMethodText(_ session: JellyfinSession) -> String? {
        switch session.playMethod {
        case "DirectPlay": return "Direct Play"
        case "DirectStream": return "Direct Stream · repackaged, not re-encoded"
        case "Transcode":
            guard let transcode = session.transcode else { return "Transcoding" }
            var parts = ["Transcoding"]
            if let bitrate = transcode.bitrate {
                parts.append(String(format: "%.1f Mb/s", Double(bitrate) / 1_000_000))
            }
            let converted = [
                transcode.isVideoDirect ? nil : transcode.videoCodec.map { "video → \($0.uppercased())" },
                transcode.isAudioDirect ? nil : transcode.audioCodec.map { "audio → \($0.uppercased())" },
            ].compactMap { $0 }
            parts += converted
            if let hw = transcode.hardwareAcceleration, hw != "none", !hw.isEmpty { parts.append(hw.uppercased()) }
            let reasons = transcode.reasons.map(Self.readableReason)
            return parts.joined(separator: " · ") + (reasons.isEmpty ? "" : "\n" + reasons.joined(separator: ", "))
        default: return nil
        }
    }

    /// "VideoCodecNotSupported" → "Video codec not supported".
    nonisolated private static func readableReason(_ reason: String) -> String {
        var words: [String] = []
        for character in reason {
            if character.isUppercase || words.isEmpty {
                words.append(String(character))
            } else {
                words[words.count - 1].append(character)
            }
        }
        return words.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }.joined(separator: " ")
    }

    private func send(_ command: JellyfinMediaClient.SessionCommand, to session: JellyfinSession) {
        guard case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        Task {
            do {
                try await client.sendPlaystateCommand(command, sessionId: session.id, credential: credential, authHeader: authHeader)
            } catch {
                actionError = "\(session.deviceName) didn't accept the command."
            }
        }
    }

    private func sendMessage(_ text: String, to session: JellyfinSession) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        Task {
            do {
                try await client.sendSessionMessage(text, sessionId: session.id, credential: credential, authHeader: authHeader)
            } catch {
                actionError = "The message couldn't be sent to \(session.deviceName)."
            }
        }
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
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        let socket = JellyfinWebSocketClient(credential: credential, authHeader: authHeader, deviceId: deviceId)
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
