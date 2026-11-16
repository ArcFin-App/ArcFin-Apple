// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import Telemetry

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var showUsersSheet = false
    @State private var languageOverride = AppLanguage.override ?? ""
    @State private var usersDetent: PresentationDetent = .medium

    var body: some View {
        List {
            rows
        }
        .arcfinListStyle()
        .screenBackground()
        .navigationTitle(authManager.state.credential?.displayName ?? "Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showUsersSheet, onDismiss: { usersDetent = .medium }) {
            NavigationStack { UsersView(onExpand: { usersDetent = .large }) }
                .presentationDetents([.medium, .large], selection: $usersDetent)
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var rows: some View {
        profileSection

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

        if AppLanguage.isChoosable {
            Section {
                languagePicker
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
            LabeledContent("Build") {
                Text(AppBuild.number).foregroundStyle(.secondary)
            }
            introductionRows
            NavigationLink {
                LicensesView()
            } label: {
                Text("Legal & Licenses")
            }
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
        } header: {
            sectionHeader("About", icon: "info.circle")
        } footer: {
            MadeByFooter()
        }

        // ── Sign Out ─────────────────────────────────────────────────
        SignOutSection()
    }

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
        Text(title).foregroundStyle(DT.Color.textPrimary)
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
                    profileCard(cred: cred)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.profile")
                NavigationLink {
                    ProfileAccessView()
                } label: {
                    HStack {
                        settingsRow("Your Profile", icon: "person.text.rectangle")
                        Spacer()
                        if ProfileRules.shared.restrictsContent {
                            Label("Parental Controls", systemImage: "lock.shield")
                                .font(.caption)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                }
                QuickConnectRow()
                ScanAppleTVCodeRow()
                SetUpNearbyAppleTVRow()
            } footer: {
                Text("Enter the code shown on another device to sign it in instantly using this account.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    private func settingsRow(_ title: LocalizedStringKey, icon: String) -> some View {
        Label {
            Text(title).foregroundStyle(DT.Color.textPrimary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(DT.Color.accent)
                .frame(width: 22)
        }
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

    private func sectionHeader(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .scaledFont(size: 12, weight: .semibold)
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

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
