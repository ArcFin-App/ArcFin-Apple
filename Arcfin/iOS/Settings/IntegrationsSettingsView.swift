// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI
import AuthCore

struct IntegrationsSettingsView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("seerrURL")            private var seerrURL             = ""

    var body: some View {
        List {
            Section {
                Toggle(isOn: $seerrDiscoverEnabled) {
                    TVRowLabelText(title: "Show Discover on Home", detail: "Adds your Seerr watchlist and its trending and popular rows to Home.")
                }
                .syncLocked("seerrDiscoverEnabled", authManager)
                NavigationLink {
                    SeerrPluginView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    HStack {
                        TVRowLabelText(title: "Seerr", detail: "Request movies and shows, and keep a watchlist.")
                        Spacer()
                        seerrStatusPill
                    }
                }
                NavigationLink {
                    TMDBSettingsView()
                } label: {
                    HStack {
                        TVRowLabelText(title: "TMDB", detail: "Streaming services and title details, without Seerr.")
                        Spacer()
                        if seerrRepo.hasTMDB {
                            Text("Connected").font(.caption2).foregroundStyle(DT.Color.palette("10b981"))
                        }
                    }
                }
            } footer: {
                Text("Both are optional.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                NavigationLink {
                    ListenBrainzSettingsView(profile: authManager.state.credential?.id)
                } label: {
                    HStack {
                        TVRowLabelText(title: "ListenBrainz", detail: "Keep a history of the music you play, for recommendations.")
                        Spacer()
                        ListenBrainzStatusPill(profile: authManager.state.credential?.id)
                    }
                }
            } header: {
                Text("Music")
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Integrations")
    }

    @ViewBuilder
    private var seerrStatusPill: some View {
        if seerrRepo.authFailed {
            Text("Auth Failed").font(.caption2).foregroundStyle(DT.Color.palette("F43F5E"))
        } else if !seerrURL.isEmpty {
            Text("Connected").font(.caption2).foregroundStyle(DT.Color.palette("10b981"))
        }
    }
}

#Preview {
    NavigationStack { IntegrationsSettingsView() }
        .environment(AuthManager())
}
