// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine
import Persistence
import SeerrAPI
import Telemetry
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var showUsersSheet = false
    @State private var signOutTarget: ServerCredential?
    @State private var languageOverride = AppLanguage.override ?? ""
    #if !os(tvOS)
    @State private var usersDetent: PresentationDetent = .medium
    #endif

    // MARK: - Persisted preferences (tvOS's single-page layout only — the iOS/iPadOS hub
    // below reads the same keys from each dedicated sub-screen instead).
#if os(tvOS)
    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
#endif
    @AppStorage("seerrURL")            private var seerrURL             = ""

    var body: some View {
#if os(tvOS)
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
        .sheet(isPresented: $showUsersSheet) {
            // frame(minWidth: 900) used to force content wider than tvOS's own sheet
            // container, clipping the text on both edges — letting it size naturally fits.
            NavigationStack { UsersView() }
        }
#else
        List {
            rows
        }
        .arcfinListStyle()
        .screenBackground()
        .navigationTitle(authManager.state.credential?.displayName ?? "Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
#endif
        .sheet(isPresented: $showUsersSheet, onDismiss: { usersDetent = .medium }) {
            NavigationStack { UsersView(onExpand: { usersDetent = .large }) }
                .presentationDetents([.medium, .large], selection: $usersDetent)
                .presentationDragIndicator(.visible)
        }
#endif
    }

    @ViewBuilder
    private var rows: some View {
        profileSection

#if os(tvOS)
        // ── Preferences ──────────────────────────────────────────────
        Section {
            NavigationLink(value: TVSettingsPage.playback) {
                settingsRow("Playback", icon: "play.circle")
            }
            NavigationLink(value: TVSettingsPage.appearance) {
                settingsRow("Appearance", icon: "paintbrush")
            }
        } header: {
            sectionHeader("Preferences", icon: "slider.horizontal.3")
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
            sectionHeader("Account & Server", icon: "person.badge.key")
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
            sectionHeader("Plugins", icon: "puzzlepiece.extension")
        }
#elseif os(iOS)
        // Grouped hub — each row below pushes to its own focused screen instead of
        // stacking every preference into one long page. The Mac's Settings window lists
        // these panes in its own sidebar.
        Section {
            NavigationLink {
                PlaybackSettingsView()
            } label: {
                settingsRow("Playback", icon: "play.circle")
            }
            NavigationLink {
                DownloadsSettingsView()
            } label: {
                settingsRow("Downloads", icon: "arrow.down.circle")
            }
            NavigationLink {
                AppearanceView()
            } label: {
                settingsRow("Appearance", icon: "paintbrush")
            }
            NavigationLink {
                NotificationsSettingsView()
            } label: {
                settingsRow("Notifications", icon: "bell")
            }
        }

        Section {
            NavigationLink {
                ServerAccountSettingsView()
            } label: {
                settingsRow("Server", icon: "person.badge.key")
            }
            NavigationLink {
                IntegrationsSettingsView()
            } label: {
                settingsRow("Integrations", icon: "puzzlepiece.extension")
            }
        }
#endif

        if AppLanguage.isChoosable {
            Section {
#if os(tvOS)
                NavigationLink(value: TVSettingsPage.language) {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text(languageOverride.isEmpty ? String(localized: "System Default") : AppLanguage.name(of: languageOverride))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
#else
                languagePicker
#endif
            } footer: {
                if languageOverride != AppLanguage.atLaunch {
                    Text("Arcfin switches language the next time it opens.")
                }
            }
        }

        // ── About ────────────────────────────────────────────────────
        Section {
            LabeledContent("Version") {
                Text(appVersion).foregroundStyle(.secondary)
            }
            .tvInfoRow()
            LabeledContent("Build") {
                Text(buildNumber).foregroundStyle(.secondary)
            }
            .tvInfoRow()
            introductionRows
#if os(tvOS)
            NavigationLink(value: TVSettingsPage.licenses) {
                Text("Licenses & Third-Party Notices")
            }
#else
            NavigationLink {
                LicensesView()
            } label: {
                Text("Licenses & Third-Party Notices")
            }
#endif
#if os(tvOS)
            LabeledContent("Support", value: "arcfin.psmattas.com/support")
                .tvInfoRow()
            LabeledContent("Privacy Policy", value: "arcfin.psmattas.com/privacy")
                .tvInfoRow()
            LabeledContent("Terms of Use", value: "arcfin.psmattas.com/terms")
                .tvInfoRow()
            LabeledContent("Data Protection", value: "arcfin.psmattas.com/data-protection")
                .tvInfoRow()
#else
            DiagnosticsRow()
            Link(destination: URL(string: "https://git.psmattas.com/ArcFin/ArcFin/issues/new/choose")!) {
                HStack {
                    TVRowLabelText(title: "Report a Problem", detail: "Opens Arcfin's issue tracker. You can sign in there with GitHub or GitLab.")
                        .foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(.caption2)).foregroundStyle(DT.Color.textSecondary)
                }
            }
            Link(destination: URL(string: "https://arcfin.psmattas.com/support")!) {
                HStack {
                    Text("Contact Support").foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(.caption2)).foregroundStyle(DT.Color.textSecondary)
                }
            }
            Link(destination: URL(string: "https://arcfin.psmattas.com/privacy")!) {
                HStack {
                    Text("Privacy Policy").foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(.caption2)).foregroundStyle(DT.Color.textSecondary)
                }
            }
            Link(destination: URL(string: "https://arcfin.psmattas.com/terms")!) {
                HStack {
                    Text("Terms of Use").foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(.caption2)).foregroundStyle(DT.Color.textSecondary)
                }
            }
            Link(destination: URL(string: "https://arcfin.psmattas.com/data-protection")!) {
                HStack {
                    Text("Data Protection").foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(.caption2)).foregroundStyle(DT.Color.textSecondary)
                }
            }
#endif
        } header: {
            sectionHeader("About", icon: "info.circle")
        } footer: {
            // A footer, not a row — an extra row with a cleared background broke the
            // section's rounded-corner silhouette at the bottom edge (a List quirk: the
            // last row's background normally supplies that corner).
            Text("Made by PSMattas")
                .font(.system(.caption2, design: .default, weight: .semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }

        // ── Sign Out ─────────────────────────────────────────────────
        Section {
            Button(role: .destructive) {
                signOutTarget = authManager.state.credential
            } label: {
                Text("Sign Out")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .confirmingProfileRemoval($signOutTarget, signingOut: true,
                                  isLastProfile: authManager.profiles.count <= 1) { _ in
            authManager.signOut()
        }
    }

#if !os(tvOS)
    private var languagePicker: some View {
        Picker(selection: $languageOverride) {
            Text("System Default").tag("")
            ForEach(AppLanguage.available, id: \.self) { code in
                Text(verbatim: AppLanguage.name(of: code)).tag(code)
            }
        } label: {
            settingsRow("Language", icon: "globe")
        }
        .onChange(of: languageOverride) { _, code in
            AppLanguage.override = code.isEmpty ? nil : code
        }
    }
#endif

#if os(tvOS)
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
#endif

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

    @ViewBuilder
    private func introductionLabel(_ title: LocalizedStringKey) -> some View {
#if os(tvOS)
        // TVSettingsRowStyle sets the colour, dark on the focused platter.
        Text(title)
#else
        Text(title).foregroundStyle(DT.Color.textPrimary)
#endif
    }

    private func show(_ presentation: AppIntroduction.Presentation) {
        switch presentation {
        case .onboarding: AppServices.introduction.showOnboarding()
        case .whatsNew: AppServices.introduction.showWhatsNew()
        }
        #if os(macOS)
        // Both show in the main window, so the Settings window steps aside.
        NSApp.keyWindow?.close()
        #endif
    }

    // MARK: - Profile section

    @ViewBuilder
    private var profileSection: some View {
        if case .authenticated(let cred) = authManager.state {
            Section {
#if os(tvOS)
                Button { showUsersSheet = true } label: {
                    Text(cred.displayName)
                }
                .accessibilityIdentifier("settings.profile")
#else
                Button { showUsersSheet = true } label: {
                    profileCard(cred: cred)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.profile")
#endif
            }
        }
    }

    // Apple TV's Settings app has no icons, so rows there are plain text like the rest of the list.
    @ViewBuilder
    private func settingsRow(_ title: LocalizedStringKey, icon: String) -> some View {
        #if os(tvOS)
        // No colour of its own: the row style turns it dark on the focused row's platter.
        Text(title)
        #else
        Label {
            Text(title).foregroundStyle(DT.Color.textPrimary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(DT.Color.accent)
                .frame(width: 22)
        }
        #endif
    }

    private func profileCard(cred: ServerCredential) -> some View {
        HStack(spacing: 12) {
            ProfileAvatar(profile: cred, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(cred.displayName)
                    .font(.system(.callout, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                    Text(cred.baseURL.host ?? cred.baseURL.absoluteString)
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.5))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
            Text("Auth Failed").font(.caption2).foregroundStyle(DT.Color.palette("EF4444"))
        } else if !seerrURL.isEmpty {
            Text("Connected").font(.caption2).foregroundStyle(DT.Color.palette("10b981"))
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, icon: String) -> some View {
        Group {
            #if os(tvOS)
            Text(title)
            #else
            Label(title, systemImage: icon)
            #endif
        }
        .scaledFont(size: 12, weight: .semibold)
        .foregroundStyle(DT.Color.textSecondary)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
#if os(tvOS)
        .padding(.horizontal, 24)
        .padding(.top, 24)
#endif
    }

    @ViewBuilder
    private func placeholderDetail(_ title: String) -> some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            ContentUnavailableView(
                title,
                systemImage: "hammer",
                description: Text("Coming soon.")
            )
        }
        .navigationTitle(title)
#if os(iOS)
        .toolbar(.hidden, for: .tabBar)
#endif
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#if !os(tvOS)
/// Builds the report before offering it, so the share sheet opens on a finished file rather
/// than sitting blank while a day of log is read.
private struct DiagnosticsRow: View {
    @State private var report: URL?
    @State private var isPreparing = false

    var body: some View {
        Group {
            if let report {
                ShareLink(item: report) {
                    label(title: "Share Diagnostics File",
                          detail: "\(report.lastPathComponent). Save or send it, then attach it to your issue or support request.")
                }
            } else {
                Button(action: prepare) {
                    label(title: isPreparing ? "Preparing Diagnostics…" : "Share Diagnostics",
                          detail: "This session's log and any crash reports, as a text file. It can include your server's address and the titles you played.")
                }
                .disabled(isPreparing)
            }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    private func label(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack {
            TVRowLabelText(title: title, detail: detail)
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
            if isPreparing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "square.and.arrow.up").font(.system(.caption2)).foregroundStyle(DT.Color.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func prepare() {
        isPreparing = true
        Task {
            report = await Diagnostics.makeReport()
            isPreparing = false
        }
    }
}
#endif

private extension View {
    /// A row that only shows a value, lined up with the text of the rows around it.
    func tvInfoRow() -> some View {
#if os(tvOS)
        padding(.horizontal, 24).padding(.vertical, 12)
#else
        self
#endif
    }
}

#if os(tvOS)
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
#endif
