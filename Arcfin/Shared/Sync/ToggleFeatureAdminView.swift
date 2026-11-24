// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// An Arcfin Sync feature that's one switch for the whole server. Off until an admin turns it on.
enum AdminToggleFeature {
    case recommendations, hidden

    var title: LocalizedStringKey {
        switch self {
        case .recommendations: "Recommendations"
        case .hidden: "Hide from Continue Watching and Next Up"
        }
    }

    var about: LocalizedStringKey {
        switch self {
        case .recommendations:
            "Rows on each person's Home picked from what they've watched, liked and favourited: Top Picks, Because You Watched, and Popular on This Server. Popular only shows titles at least two other people played in the last 30 days, so no one's viewing is shown on its own."
        case .hidden:
            "People can hide titles from Continue Watching and Next Up in Arcfin. What they hide is kept on this server, so it's the same on all their devices."
        }
    }

    func load(_ client: ArcfinCompanionClient, credential: ServerCredential, authHeader: String) async throws -> Bool {
        switch self {
        case .recommendations: try await client.recommendationsEnabled(credential: credential, authHeader: authHeader)
        case .hidden: try await client.hiddenEnabled(credential: credential, authHeader: authHeader)
        }
    }

    func save(_ on: Bool, _ client: ArcfinCompanionClient, credential: ServerCredential, authHeader: String) async throws -> Bool {
        switch self {
        case .recommendations: try await client.setRecommendationsEnabled(on, credential: credential, authHeader: authHeader)
        case .hidden: try await client.setHiddenEnabled(on, credential: credential, authHeader: authHeader)
        }
    }
}

/// Arcfin for Everyone › Recommendations or Hide from Continue Watching and Next Up: one switch.
struct ToggleFeatureAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let feature: AdminToggleFeature
    @State private var enabled: Bool?
    @State private var error: String?
    @State private var actionError: String?
    private let client = ArcfinCompanionClient()

    var body: some View {
        SettingsForm {
            if let enabled {
                Section {
                    Toggle(isOn: Binding(get: { enabled }, set: { save($0) })) {
                        TVRowLabelText(title: feature.title)
                    }
                    .tvListRow()
                } footer: {
                    Text(feature.about)
                }
            } else {
                AdminPendingSection(error: error)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(feature.title)
        .task { await load() }
        .adminErrorAlert($actionError)
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            enabled = try await feature.load(client, credential: access.credential, authHeader: access.header)
        } catch {
            self.error = AdminSyncError.loadMessage()
        }
    }

    private func save(_ on: Bool) {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        let before = enabled
        enabled = on
        Task {
            do {
                enabled = try await feature.save(on, client, credential: access.credential, authHeader: access.header)
            } catch {
                enabled = before
                actionError = AdminSyncError.message(error)
            }
        }
    }
}
