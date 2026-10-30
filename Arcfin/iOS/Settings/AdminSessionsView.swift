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

    @State private var model = AdminSessionsModel()
    @State private var messageTarget: JellyfinSession?
    @State private var messageText = ""

    var body: some View {
        List {
            if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            } else if model.sessions.isEmpty && !model.isLoading {
                Section {
                    Text("No active sessions.")
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            } else {
                ForEach(model.sessions) { session in
                    AdminSessionRow(session: session, receivedAt: model.receivedAt)
                        .contextMenu { if session.supportsRemoteControl { sessionActions(session) } }
                        .swipeActions {
                            if session.supportsRemoteControl, session.nowPlayingItemName != nil {
                                Button(session.isPaused ? "Resume" : "Pause",
                                       systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                                    model.send(session.isPaused ? .unpause : .pause, to: session, authManager: authManager)
                                }
                                .tint(DT.Color.accent)
                            }
                        }
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Active Sessions")
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
        .alert("Send a Message", isPresented: Binding(get: { messageTarget != nil }, set: { if !$0 { messageTarget = nil } })) {
            TextField("Message", text: $messageText)
            Button("Send") {
                if let messageTarget { model.sendMessage(messageText, to: messageTarget, authManager: authManager) }
                messageText = ""
            }
            Button("Cancel", role: .cancel) { messageText = "" }
        } message: {
            Text("Shows on \(messageTarget?.deviceName ?? "the device") for 15 seconds.")
        }
        .alert("Couldn't Reach That Session", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        .onAppear {
            model.startLiveUpdates(authManager: authManager)
            model.startAutoRefresh(authManager: authManager)
        }
        .onDisappear {
            model.stopAutoRefresh()
            model.stopLiveUpdates()
        }
    }

    @ViewBuilder
    private func sessionActions(_ session: JellyfinSession) -> some View {
        if session.nowPlayingItemName != nil {
            Button(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                model.send(session.isPaused ? .unpause : .pause, to: session, authManager: authManager)
            }
            Button("Stop Playback", systemImage: "stop.fill", role: .destructive) { model.send(.stop, to: session, authManager: authManager) }
        }
        Button("Send Message…", systemImage: "text.bubble") { messageTarget = session }
    }
}

#Preview {
    NavigationStack { AdminSessionsView() }
        .environment(AuthManager())
}
