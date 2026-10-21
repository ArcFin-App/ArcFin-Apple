// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct IntegrationsSettingsView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("seerrURL")            private var seerrURL             = ""
    @AppStorage("streamystatsURL")     private var streamystatsURL      = ""

    var body: some View {
        List {
            Section {
                Toggle("Show Discover on Home", isOn: $seerrDiscoverEnabled)
                    .syncLocked("seerrDiscoverEnabled", authManager)
                NavigationLink {
                    SeerrPluginView()
                        #if os(iOS)
                        .toolbar(.hidden, for: .tabBar)
                        #endif
                } label: {
                    HStack {
                        Text("Seerr")
                        Spacer()
                        seerrStatusPill
                    }
                }
                NavigationLink {
                    StreamystatsPluginView()
                        #if os(iOS)
                        .toolbar(.hidden, for: .tabBar)
                        #endif
                } label: {
                    HStack {
                        Text("Streamystats")
                        Spacer()
                        if !streamystatsURL.isEmpty {
                            Text("Connected").font(.caption2).foregroundStyle(Color(hex: "10b981"))
                        }
                    }
                }
                NavigationLink {
                    TMDBSettingsView()
                } label: {
                    HStack {
                        Text("TMDB")
                        Spacer()
                        if seerrRepo.hasTMDB {
                            Text("Connected").font(.caption2).foregroundStyle(Color(hex: "10b981"))
                        }
                    }
                }
            } footer: {
                Text("Connect Seerr for requests, Streamystats for play stats and TMDB for streaming and title details without Seerr. All are optional.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Integrations")
    }

    @ViewBuilder
    private var seerrStatusPill: some View {
        if seerrRepo.authFailed {
            Text("Auth Failed").font(.caption2).foregroundStyle(Color(hex: "EF4444"))
        } else if !seerrURL.isEmpty {
            Text("Connected").font(.caption2).foregroundStyle(Color(hex: "10b981"))
        }
    }
}

#Preview {
    NavigationStack { IntegrationsSettingsView() }
        .environment(AuthManager())
}
