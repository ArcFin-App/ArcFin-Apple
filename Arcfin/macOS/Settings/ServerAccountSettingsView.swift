// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

struct ServerAccountSettingsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var showSwitchServerSheet = false

    private var distinctServerCount: Int {
        Set(authManager.profiles.map { $0.baseURL.host ?? $0.baseURL.absoluteString }).count
    }

    var body: some View {
        List {
            Section {
                serverRow
                Button { showSwitchServerSheet = true } label: {
                    TVRowLabelText(title: "Switch Server", detail: "Move to another server you've signed in to.")
                }
                .disabled(distinctServerCount <= 1)
                NavigationLink {
                    AddServerFlowView()
                } label: {
                    TVRowLabelText(title: "Add Server", detail: "Sign in to another Jellyfin server.")
                }
                if let activeID = authManager.state.credential?.id {
                    NavigationLink {
                        ServerSettingsView(profileID: activeID)
                    } label: {
                        TVRowLabelText(title: "Server Settings", detail: "Addresses, home Wi-Fi, custom headers and settings sync.")
                    }
                }
                if authManager.isAdmin {
                    NavigationLink {
                        AdminSessionsView()
                    } label: {
                        TVRowLabelText(title: "Active Sessions", detail: "Who's watching on your server right now.")
                    }
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Server")
        .sheet(isPresented: $showSwitchServerSheet) {
            NavigationStack { SwitchServerView() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var serverRow: some View {
        if case .authenticated(let cred) = authManager.state {
            LabeledContent("Server") {
                Text(cred.baseURL.host ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    NavigationStack { ServerAccountSettingsView() }
}
