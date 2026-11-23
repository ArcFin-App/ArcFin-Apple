// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

struct ServerSettingsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var model = ServerSettingsModel()

    private var activeBaseURL: URL? { authManager.state.credential?.baseURL }

    // No Local and Remote URLs here: switching between them by home Wi-Fi network is
    // iPhone and iPad only, so on Apple TV they'd be saved and never used.
    var body: some View {
        List {
            ServerPublicInfoSection(model: model)

            ArcfinSyncSection(showsAdminLink: true)

            Section {
                NavigationLink { ServerConnectionView().tvSettingsPage() } label: {
                    TVRowLabelText(title: "Server & Connection", detail: "Test your speed to the server, and see what your account and this device can play.")
                }
                NavigationLink { CustomHeadersView().tvSettingsPage() } label: {
                    TVRowLabelText(title: "Custom Headers", detail: "Extra headers for a server behind an access gateway, such as Cloudflare Access.")
                }
                if let activeBaseURL {
                    LabeledContent("Address", value: activeBaseURL.absoluteString)
                        .tvReadOnlyRow()
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Server Settings")
        .task { await model.loadInfo(baseURL: activeBaseURL) }
    }
}
