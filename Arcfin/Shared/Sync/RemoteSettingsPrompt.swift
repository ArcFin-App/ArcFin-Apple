// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SyncEngine

/// Ask First: settings were changed on another device, and this one asks before using them.
struct RemoteSettingsPrompt: ViewModifier {
    @Environment(AuthManager.self) private var authManager
    let canAsk: Bool
    /// Something else is presented over the window. Read when the question is about to come up,
    /// not while it's showing, since it then covers the window itself.
    var isCovered: @MainActor () -> Bool = { false }
    @State private var isPresented = false

    private var title: String {
        let name = authManager.pendingRemoteSettings?.deviceName ?? ""
        return name.isEmpty ? String(localized: "Settings Changed on Another Device")
                            : String(localized: "Settings Changed on \(name)")
    }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                Button("Use Them") { authManager.answerRemoteSettings(useThem: true) }
                Button("Keep This Device's", role: .cancel) { authManager.answerRemoteSettings(useThem: false) }
            } message: {
                Text("Use them on this device?")
            }
            .task(id: canAsk) {
                // Waits out a sheet or cover over the window, then asks once.
                while canAsk, !isPresented, !Task.isCancelled {
                    if !isCovered() {
                        isPresented = true
                        return
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .onChange(of: authManager.pendingRemoteSettings == nil) { _, answered in
                if answered { isPresented = false }
            }
            // The lock, Who's Watching or the player came up: the question waits for them to go.
            .onChange(of: canAsk) { _, can in
                if !can { isPresented = false }
            }
    }
}
