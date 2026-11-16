// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var showUsersSheet = false
    @State private var languageOverride = AppLanguage.override ?? ""

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("seerrURL")            private var seerrURL             = ""

    var body: some View {
        // A ScrollView rather than a List: the List faded out its top rows under where the
        // tab bar sits, even with the tab bar hidden.
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                rows
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.vertical, 40)
        }
        .buttonStyle(TVSettingsRowStyle())
        // Declared outside the row style so the pages it opens keep the system styles.
        .navigationDestination(for: TVSettingsPage.self, destination: page)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .appSheet(isPresented: $showUsersSheet) {
            NavigationStack { UsersView() }
        }
    }

    @ViewBuilder
    private var rows: some View {
        profileSection

        // ── Preferences ──────────────────────────────────────────────
        Section {
            NavigationLink(value: TVSettingsPage.playback) {
                settingsRow("Playback")
            }
            NavigationLink(value: TVSettingsPage.appearance) {
                settingsRow("Appearance")
            }
        } header: {
            sectionHeader("Preferences")
        }

        // ── Account & Server ─────────────────────────────────────────
        Section {
            serverRow
            NavigationLink(value: TVSettingsPage.profile) {
                HStack {
                    Text("Your Profile")
                    Spacer()
                    if ProfileRules.shared.restrictsContent {
                        Label("Parental Controls", systemImage: "lock.shield")
                            .font(.caption2)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
            }
            if let activeID = authManager.state.credential?.id {
                NavigationLink(value: TVSettingsPage.serverSettings(activeID)) {
                    Text("Server Settings")
                }
            }
            Button { showUsersSheet = true } label: {
                Text("Switch Server")
            }
            NavigationLink(value: TVSettingsPage.addServer) {
                Text("Add Server")
            }
        } header: {
            sectionHeader("Account & Server")
        }

        // ── Plugins ──────────────────────────────────────────────────
        Section {
            Toggle(isOn: $seerrDiscoverEnabled) {
                TVRowLabelText(title: "Show Discover on Home", detail: "Adds your Seerr watchlist and its trending and popular rows to Home.")
            }
            NavigationLink(value: TVSettingsPage.seerr) {
                HStack {
                    Text("Seerr")
                    Spacer()
                    seerrStatusPill
                }
            }
            NavigationLink(value: TVSettingsPage.tmdb) {
                HStack {
                    Text("TMDB")
                    Spacer()
                    if seerrRepo.hasTMDB {
                        Text("Connected").font(.caption2).foregroundStyle(DT.Color.palette("10b981"))
                    }
                }
            }
        } header: {
            sectionHeader("Plugins")
        }

        if AppLanguage.isChoosable {
            Section {
                NavigationLink(value: TVSettingsPage.language) {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text(languageOverride.isEmpty ? String(localized: "System Default") : AppLanguage.name(of: languageOverride))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
            } footer: {
                if languageOverride != AppLanguage.atLaunch {
                    Text("Arcfin switches language the next time it opens.")
                }
            }
        }

        // ── About ────────────────────────────────────────────────────
        Section {
            LabeledContent("Version") {
                Text(AppBuild.version).foregroundStyle(.secondary)
            }
            .tvInfoRow()
            LabeledContent("Build") {
                Text(AppBuild.number).foregroundStyle(.secondary)
            }
            .tvInfoRow()
            introductionRows
            NavigationLink(value: TVSettingsPage.licenses) {
                Text("Legal & Licenses")
            }
            LabeledContent("Support", value: "arcfin.psmattas.com/support")
                .tvInfoRow()
        } header: {
            sectionHeader("About")
        } footer: {
            MadeByFooter()
        }

        // ── Sign Out ─────────────────────────────────────────────────
        SignOutSection()
    }

    private func page(_ page: TVSettingsPage) -> some View {
        pageContent(page).tvSettingsPage()
    }

    @ViewBuilder
    private func pageContent(_ page: TVSettingsPage) -> some View {
        switch page {
        case .playback: PlaybackSettingsView()
        case .appearance: AppearanceView()
        case .profile: ProfileAccessView()
        case .serverSettings(let profileID): ServerSettingsView(profileID: profileID)
        case .addServer: AddServerFlowView()
        case .seerr: SeerrPluginView()
        case .tmdb: TMDBSettingsView()
        case .licenses: LicensesView()
        case .language:
            TVChoicePage(title: "Language", selection: $languageOverride, options: [""] + AppLanguage.available) { code in
                code.isEmpty ? Text("System Default") : Text(verbatim: AppLanguage.name(of: code))
            }
            .onChange(of: languageOverride) { _, code in
                AppLanguage.override = code.isEmpty ? nil : code
            }
        }
    }

    // MARK: - Tour and What's New

    @ViewBuilder
    private var introductionRows: some View {
        Button { show(.whatsNew) } label: {
            introductionLabel("What's New in Arcfin")
        }
        Button { show(.onboarding) } label: {
            introductionLabel("Take the Tour Again")
        }
    }

    private func introductionLabel(_ title: LocalizedStringKey) -> some View {
        // TVSettingsRowStyle sets the colour, dark on the focused platter.
        Text(title)
    }

    private func show(_ presentation: AppIntroduction.Presentation) {
        switch presentation {
        case .onboarding: AppServices.introduction.showOnboarding()
        case .whatsNew: AppServices.introduction.showWhatsNew()
        }
    }

    // MARK: - Profile section

    @ViewBuilder
    private var profileSection: some View {
        if case .authenticated(let cred) = authManager.state {
            Section {
                Button { showUsersSheet = true } label: {
                    Text(cred.displayName)
                }
                .accessibilityIdentifier("settings.profile")
            }
        }
    }

    // Apple TV's Settings app has no icons, so rows here are plain text like the rest of the list.
    private func settingsRow(_ title: LocalizedStringKey) -> some View {
        // No colour of its own: the row style turns it dark on the focused row's platter.
        Text(title)
    }

    // MARK: - Row builders

    @ViewBuilder
    private var serverRow: some View {
        if case .authenticated(let cred) = authManager.state {
            LabeledContent("Server") {
                Text(cred.baseURL.host ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .tvInfoRow()
        }
    }

    @ViewBuilder
    private var seerrStatusPill: some View {
        if seerrRepo.authFailed {
            Text("Auth Failed").font(.caption2).foregroundStyle(DT.Color.palette("F43F5E"))
        } else if !seerrURL.isEmpty {
            Text("Connected").font(.caption2).foregroundStyle(DT.Color.palette("10b981"))
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .scaledFont(size: 12, weight: .semibold)
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 24)
            .padding(.top, 24)
    }
}

private extension View {
    /// A row that only shows a value, lined up with the text of the rows around it.
    func tvInfoRow() -> some View {
        padding(.horizontal, 24).padding(.vertical, 12)
    }
}

private enum TVSettingsPage: Hashable {
    case playback, appearance, profile, serverSettings(UUID), addServer, seerr, tmdb, language, licenses
}

// Settings rows in the tvOS ScrollView: plain text at rest and the light platter of the
// system's own lists when focused.
private struct TVSettingsRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVSettingsRow(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct TVSettingsRow<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label
            .foregroundStyle(isFocused ? Color.black : DT.Color.textPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.92) : Color.clear)
            )
            .scaleEffect(isPressed ? 0.98 : (isFocused ? 1.02 : 1))
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}
