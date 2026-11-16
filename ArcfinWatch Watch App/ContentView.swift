// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The devices playing on this profile. With one, its Now Playing straight away.
struct ContentView: View {
    @Environment(WatchRemote.self) private var remote
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: "Arcfin"))
        }
        .task(id: scenePhase == .active && WatchSignIn.shared.credential != nil) {
            if scenePhase == .active, WatchSignIn.shared.credential != nil { remote.start() } else { remote.stop() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if WatchSignIn.shared.credential == nil {
            message("Open Arcfin on your iPhone and sign in to use the remote.", systemImage: "iphone")
        } else if !remote.hasLoaded {
            ProgressView()
        } else if remote.sessions.isEmpty, remote.cannotReachServer {
            ContentUnavailableView {
                Label("Can’t Reach Your Server", systemImage: "wifi.exclamationmark")
            } actions: {
                Button("Try Again") { Task { await remote.refresh() } }
            }
        } else if remote.sessions.isEmpty {
            ContentUnavailableView("Nothing Playing", systemImage: "av.remote",
                                   description: Text("Play something in Arcfin on another device."))
        } else if remote.sessions.count == 1, let only = remote.sessions.first {
            NowPlayingView(sessionID: only.id)
        } else {
            List(remote.sessions) { session in
                NavigationLink {
                    NowPlayingView(sessionID: session.id)
                } label: {
                    DeviceRow(session: session)
                }
            }
            .navigationTitle("Devices")
        }
    }

    private func message(_ text: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct DeviceRow: View {
    let session: WatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(session.deviceName, systemImage: session.isPaused ? "pause.fill" : "play.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
            Text(session.title)
                .font(.headline)
                .lineLimit(2)
        }
    }
}
