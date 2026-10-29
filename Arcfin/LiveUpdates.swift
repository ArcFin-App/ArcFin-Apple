// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import os
import AuthCore
import JellyfinAPI
import Telemetry

/// Keeps Home current while the app is open: watching or favouriting on another device, or
/// titles arriving on the server, update the shelves without a pull to refresh.
@MainActor
final class LiveUpdates {
    private let mediaRepo: MediaRepository
    private var socket: JellyfinWebSocketClient?
    private var connectionTask: Task<Void, Never>?
    private var watchStateTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?
    private let log = Telemetry.logger(category: "LiveUpdates")

    init(mediaRepo: MediaRepository) {
        self.mediaRepo = mediaRepo
    }

    func connect(credential: ServerCredential, authClient: JellyfinAuthClient) {
        disconnect()
        connectionTask = Task { [weak self] in
            var retryDelay = 5
            while !Task.isCancelled {
                guard let self else { return }
                let opened = Date.now
                await self.listen(credential: credential, authClient: authClient)
                guard !Task.isCancelled else { return }
                // A connection that lasted a while dropped for a passing reason; one that
                // closed straight away (a proxy without WebSocket support) backs off.
                retryDelay = Date.now.timeIntervalSince(opened) > 60 ? 5 : min(retryDelay * 2, 300)
                self.log.info("Socket closed; reconnecting in \(retryDelay, privacy: .public) s")
                try? await Task.sleep(for: .seconds(retryDelay))
            }
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        watchStateTask?.cancel()
        libraryTask?.cancel()
        socket?.close()
        socket = nil
    }

    private func listen(credential: ServerCredential, authClient: JellyfinAuthClient) async {
        let deviceId = UserDefaults.standard.string(forKey: "arcfin.deviceId") ?? UUID().uuidString
        let authHeader = authClient.authHeader(token: credential.accessToken)
        let socket = JellyfinWebSocketClient(credential: credential, authHeader: authHeader, deviceId: deviceId)
        self.socket = socket
        await withTaskCancellationHandler {
            for await event in socket.events {
                switch event {
                case .userDataChanged:
                    scheduleWatchStateRefresh(credential: credential, authClient: authClient)
                case .libraryChanged:
                    scheduleLibraryRefresh(credential: credential, authClient: authClient)
                default:
                    break
                }
            }
        } onCancel: {
            socket.close()
        }
    }

    // Progress saves arrive every few seconds while something plays anywhere, so changes are
    // gathered and Home refreshes at most once per window.
    private func scheduleWatchStateRefresh(credential: ServerCredential, authClient: JellyfinAuthClient) {
        guard watchStateTask == nil else { return }
        watchStateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            await self.mediaRepo.refreshWatchState(credential: credential, authClient: authClient)
            self.watchStateTask = nil
        }
    }

    // The server sends LibraryChanged in bursts during a scan.
    private func scheduleLibraryRefresh(credential: ServerCredential, authClient: JellyfinAuthClient) {
        guard libraryTask == nil else { return }
        libraryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            await self.mediaRepo.refreshRecentlyAdded(credential: credential, authClient: authClient)
            self.libraryTask = nil
        }
    }
}

/// ContentView reconnects when the profile changes and drops the socket in the background.
struct LiveUpdatesKey: Hashable {
    let credentialID: UUID?
    let isActive: Bool
}
