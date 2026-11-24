// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Arcfin for Everyone › Pick Together: who on this server may use it. The same switch as the
/// Pick Together tab on the Arcfin Sync plugin's page in the Jellyfin dashboard.
struct PickTogetherAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let users: [ArcfinSyncAdminUser]

    @State private var settings: PickTogetherAdminSettings?
    @State private var error: String?
    private let client = PickTogetherClient()

    var body: some View {
        SettingsForm {
            if let settings {
                Section {
                    Toggle("Pick Together", isOn: Binding(get: { settings.enabled }, set: { on in
                        save { $0.enabled = on }
                    }))
                    .tvListRow()
                } footer: {
                    Text("People on this server swipe through titles on iPhone and iPad until they agree on one. Each person only sees titles they're allowed to see.")
                }
                if settings.enabled {
                    Section {
                        ForEach(users) { user in
                            Toggle(isOn: Binding(get: { !settings.disabledUsers.contains(user.userId) }, set: { on in
                                save { s in
                                    s.disabledUsers.removeAll { $0 == user.userId }
                                    if !on { s.disabledUsers.append(user.userId) }
                                }
                            })) {
                                Text(verbatim: user.name)
                            }
                            .tvListRow()
                        }
                    } header: {
                        Text("Who Can Use It")
                    } footer: {
                        Text("Turned off for someone, it's gone from their Arcfin and the server refuses it.")
                    }
                }
            } else if let error {
                Section {
                    Text(error)
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
            } else {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .tvReadOnlyRow()
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Pick Together")
        .task { await load() }
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            settings = try await client.adminSettings(credential: access.credential, authHeader: access.header)
        } catch {
            self.error = String(localized: "Couldn't load who can use Pick Together. Check your connection, and that this profile is still an admin.")
        }
    }

    /// Changes the setting straight away, and puts it back if the server doesn't take it.
    private func save(_ change: (inout PickTogetherAdminSettings) -> Void) {
        guard var next = settings, let access = authManager.arcfinSyncDevicesSession else { return }
        let before = next
        change(&next)
        settings = next
        Task {
            do {
                settings = try await client.saveAdminSettings(next, credential: access.credential, authHeader: access.header)
            } catch {
                settings = before
            }
        }
    }
}
