// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// An Arcfin Sync feature an admin turns on or off, for everyone or for some people.
enum AdminAccessFeature {
    case pickTogether, watchParty

    var title: LocalizedStringKey {
        switch self {
        case .pickTogether: "Pick Together"
        case .watchParty: "Watch Parties"
        }
    }

    var about: LocalizedStringKey {
        switch self {
        case .pickTogether:
            "People on this server swipe through titles on iPhone and iPad until they agree on one. Each person only sees titles they're allowed to see."
        case .watchParty:
            "Someone picks a title and shares a code; others join with it, and everyone watches together with SyncPlay. Only people who can see the title can join. There are no links."
        }
    }

    var usersHeader: LocalizedStringKey {
        switch self {
        case .pickTogether: "Who Can Use It"
        case .watchParty: "Who Can Use Them"
        }
    }

    var usersFooter: LocalizedStringKey {
        switch self {
        case .pickTogether: "Turned off for someone, it's gone from their Arcfin and the server refuses it."
        case .watchParty: "Turned off for someone, watch parties are gone from their Arcfin and the server refuses them."
        }
    }

    var loadError: String {
        switch self {
        case .pickTogether:
            String(localized: "Couldn't load who can use Pick Together. Check your connection, and that this profile is still an admin.")
        case .watchParty:
            String(localized: "Couldn't load who can use watch parties. Check your connection, and that this profile is still an admin.")
        }
    }

    func load(credential: ServerCredential, authHeader: String) async throws -> PickTogetherAdminSettings {
        switch self {
        case .pickTogether: try await PickTogetherClient().adminSettings(credential: credential, authHeader: authHeader)
        case .watchParty: try await ArcfinCompanionClient().watchPartyAdmin(credential: credential, authHeader: authHeader)
        }
    }

    func save(_ settings: PickTogetherAdminSettings, credential: ServerCredential, authHeader: String) async throws -> PickTogetherAdminSettings {
        switch self {
        case .pickTogether: try await PickTogetherClient().saveAdminSettings(settings, credential: credential, authHeader: authHeader)
        case .watchParty: try await ArcfinCompanionClient().saveWatchPartyAdmin(settings, credential: credential, authHeader: authHeader)
        }
    }
}

/// Arcfin for Everyone › Pick Together or Watch Parties: who on this server may use it. The same
/// switches as the Features tab on the Arcfin Sync plugin's page in the Jellyfin dashboard.
struct FeatureAccessAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let feature: AdminAccessFeature
    let users: [ArcfinSyncAdminUser]

    @State private var settings: PickTogetherAdminSettings?
    @State private var error: String?

    var body: some View {
        SettingsForm {
            if let settings {
                Section {
                    Toggle(isOn: Binding(get: { settings.enabled }, set: { on in save { $0.enabled = on } })) {
                        TVRowLabelText(title: feature.title)
                    }
                    .tvListRow()
                } footer: {
                    Text(feature.about)
                }
                if settings.enabled {
                    Section {
                        ForEach(users) { user in
                            Toggle(isOn: Binding(get: { !isOff(user.userId, in: settings) }, set: { on in
                                save { s in
                                    s.disabledUsers.removeAll { ArcfinCompanionClient.normalized($0) == ArcfinCompanionClient.normalized(user.userId) }
                                    if !on { s.disabledUsers.append(user.userId) }
                                }
                            })) {
                                TVRowLabelText(verbatim: user.name)
                            }
                            .tvListRow()
                        }
                    } header: {
                        Text(feature.usersHeader)
                    } footer: {
                        Text(feature.usersFooter)
                    }
                }
            } else {
                AdminPendingSection(error: error)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(feature.title)
        .task { await load() }
    }

    private func isOff(_ userID: String, in settings: PickTogetherAdminSettings) -> Bool {
        settings.disabledUsers.contains { ArcfinCompanionClient.normalized($0) == ArcfinCompanionClient.normalized(userID) }
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            settings = try await feature.load(credential: access.credential, authHeader: access.header)
        } catch {
            self.error = feature.loadError
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
                settings = try await feature.save(next, credential: access.credential, authHeader: access.header)
            } catch {
                settings = before
            }
        }
    }
}
