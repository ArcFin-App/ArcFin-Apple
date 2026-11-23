// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SyncEngine

/// Ask First: settings were changed on another device, and this one asks before using them.
struct RemoteSettingsPrompt: ViewModifier {
    @Environment(AuthManager.self) private var authManager
    let isPresented: Binding<Bool>

    private var title: String {
        let name = authManager.pendingRemoteSettings?.deviceName ?? ""
        return name.isEmpty ? String(localized: "Settings Changed on Another Device")
                            : String(localized: "Settings Changed on \(name)")
    }

    func body(content: Content) -> some View {
        content.alert(title, isPresented: isPresented) {
            Button("Use Them") { authManager.answerRemoteSettings(useThem: true) }
            Button("Keep This Device's", role: .cancel) { authManager.answerRemoteSettings(useThem: false) }
        } message: {
            Text("Use them on this device?")
        }
    }
}
