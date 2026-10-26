// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine
import Persistence
import SeerrAPI
import Telemetry

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var showUsersSheet = false
    @State private var languageOverride = AppLanguage.override ?? ""
    #if !os(tvOS)
    @State private var usersDetent: PresentationDetent = .medium
    #endif
    #if os(tvOS)
    @State private var listID = UUID()
    #endif

    // MARK: - Persisted preferences (tvOS's single-page layout only — the iOS/iPadOS hub
    // below reads the same keys from each dedicated sub-screen instead).
#if os(tvOS)
    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
#endif
    @AppStorage("seerrURL")            private var seerrURL             = ""

    var body: some View {
        List {
            profileSection

#if os(tvOS)
            // ── Preferences ──────────────────────────────────────────────
            Section {
                NavigationLink {
                    PlaybackSettingsView()
                } label: {
                    settingsRow("Playback", icon: "play.circle")
                }
                .listRowBackground(Color.clear)
                NavigationLink {
                    AppearanceView()
                } label: {
                    settingsRow("Appearance", icon: "paintbrush")
                }
                .listRowBackground(Color.clear)
            } header: {
                sectionHeader("Preferences", icon: "slider.horizontal.3")
            }

            // ── Account & Server ─────────────────────────────────────────
            Section {
                serverRow
                NavigationLink {
                    ProfileAccessView()
                } label: {
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
                .listRowBackground(Color.clear)
                if let activeID = authManager.state.credential?.id {
                    NavigationLink {
                        ServerSettingsView(profileID: activeID)
                    } label: {
                        Text("Server Settings")
                    }
                    .listRowBackground(Color.clear)
                }
                Button { showUsersSheet = true } label: {
                    Text("Switch Server")
                }
                .listRowBackground(Color.clear)
                NavigationLink {
                    AddServerFlowView()
                } label: {
                    Text("Add Server")
                }
                .listRowBackground(Color.clear)
            } header: {
                sectionHeader("Account & Server", icon: "person.badge.key")
            }

            // ── Plugins ──────────────────────────────────────────────────
            Section {
                Toggle(isOn: $seerrDiscoverEnabled) {
                    TVRowLabelText(title: "Show Discover on Home", detail: "Adds your Seerr watchlist and its trending and popular rows to Home.")
                }
                NavigationLink {
                    SeerrPluginView()
                } label: {
                    HStack {
                        Text("Seerr")
                        Spacer()
                        seerrStatusPill
                    }
                }
                .listRowBackground(Color.clear)
                NavigationLink {
                    TMDBSettingsView()
                } label: {
                    HStack {
                        Text("TMDB")
                        Spacer()
                        if seerrRepo.hasTMDB {
                            Text("Connected").font(.caption2).foregroundStyle(DT.Color.palette("10b981"))
                        }
                    }
                }
                .listRowBackground(Color.clear)
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
                    Picker(selection: $languageOverride) {
                        Text("System Default").tag("")
                        ForEach(AppLanguage.available, id: \.self) { code in
                            Text(verbatim: AppLanguage.name(of: code)).tag(code)
                        }
                    } label: {
                        settingsRow("Language", icon: "globe")
                    }
                    .tvListRow()
                    .onChange(of: languageOverride) { _, code in
                        AppLanguage.override = code.isEmpty ? nil : code
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
                    Text(appVersion).foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(buildNumber).foregroundStyle(.secondary)
                }
                NavigationLink {
                    LicensesView()
                } label: {
                    Text("Licenses & Third-Party Notices")
                }
#if os(tvOS)
                .listRowBackground(Color.clear)
#endif
#if os(tvOS)
                LabeledContent("Support", value: "arcfin.psmattas.com/support")
                    .listRowBackground(Color.clear)
                LabeledContent("Privacy Policy", value: "arcfin.psmattas.com/privacy")
                    .listRowBackground(Color.clear)
                LabeledContent("Terms of Use", value: "arcfin.psmattas.com/terms")
                    .listRowBackground(Color.clear)
                LabeledContent("Data Protection", value: "arcfin.psmattas.com/data-protection")
                    .listRowBackground(Color.clear)
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
                    authManager.signOut()
                } label: {
                    Text("Sign Out")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
#if os(tvOS)
                .listRowBackground(Color.clear)
#endif
            }
        }
        .arcfinListStyle()
        .screenBackground()
#if os(tvOS)
        // The page has no title, but its navigation bar still kept an empty band at the top,
        // and on the first visit it didn't hide on scroll: rows stopped short of the top and a
        // row focused up there was out of sight. A List also clips its rows to its frame, so
        // they're let through to the top once the tab bar hides. Pushed pages keep their bars.
        .toolbar(.hidden, for: .navigationBar)
        .scrollClipDisabled()
        .id(listID)
        .onAppear { listID = UUID() }
        .sheet(isPresented: $showUsersSheet) {
            // frame(minWidth: 900) used to force content wider than tvOS's own sheet
            // container, clipping the text on both edges — letting it size naturally fits.
            NavigationStack { TVUsersView() }
        }
#else
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

    // MARK: - Profile section

    @ViewBuilder
    private var profileSection: some View {
        if case .authenticated(let cred) = authManager.state {
            Section {
#if os(tvOS)
                Button { showUsersSheet = true } label: {
                    TVFocusRowLabel { Text(cred.displayName) }
                }
                .tvListRow()
#else
                Button { showUsersSheet = true } label: {
                    profileCard(cred: cred)
                }
                .buttonStyle(.plain)
#endif
            }
        }
    }

    // Apple TV's Settings app has no icons, so rows there are plain text like the rest of the list.
    @ViewBuilder
    private func settingsRow(_ title: LocalizedStringKey, icon: String) -> some View {
        #if os(tvOS)
        Text(title).foregroundStyle(DT.Color.textPrimary)
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

// MARK: - Settings models

enum VideoQuality: String, CaseIterable, Identifiable {
    case max = "Max", auto, p4k = "4K", p1080 = "1080p", p720 = "720p", p480 = "480p"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .max:   String(localized: "Max Quality")
        case .auto:  String(localized: "Auto (Recommended)")
        case .p4k:   String(localized: "4K Ultra HD")
        case .p1080: String(localized: "1080p HD")
        case .p720:  String(localized: "720p")
        case .p480:  String(localized: "480p")
        }
    }
    /// Source pixel height this tier requires — nil for Auto/Max, which have no fixed
    /// resolution floor. Used to hide tiers the current item's source can't actually supply
    /// (no point offering 4K for a 1080p source).
    var minSourceHeight: Int? {
        switch self {
        case .max, .auto: nil
        case .p4k:   2160
        case .p1080: 1080
        case .p720:  720
        case .p480:  480
        }
    }
}

// MARK: - Seerr plugin view

struct SeerrPluginView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    @AppStorage("seerrURL")         private var seerrURL        = ""
    @AppStorage("seerrUsername")    private var seerrUsername   = ""
    @AppStorage("seerrAuthMethod")  private var seerrAuthMethod = SeerrAuthMethod.jellyfin

    // Draft copies — edits only commit to AppStorage (and re-trigger the live
    // connection) on Save, so browsing the form can't accidentally reconfigure it.
    @State private var isEditing = false
    @State private var draftURL = ""
    @State private var draftUsername = ""
    @State private var draftPassword = ""
    @State private var draftAuthMethod = SeerrAuthMethod.jellyfin
    @State private var showRemoveConfirm = false

    @State private var testResult: String? = nil
    @State private var isTesting = false

    private var isConfigured: Bool { !seerrURL.isEmpty }

    /// The connection is edited as one form (Edit → Save), not per-field toggles, so a lock on
    /// any one of its three synced keys locks editing the whole thing rather than just that field.
    private var isLocked: Bool {
        ["seerrURL", "seerrUsername", "seerrAuthMethod"].contains { authManager.arcfinSyncLockedKeys.contains($0) }
    }

    var body: some View {
        List {
            if isConfigured && !isEditing {
                connectedSummary
            } else {
                editingForm
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Seerr")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isEditing || !isConfigured {
                    Button("Save") { save() }
                        .disabled(draftURL.isEmpty || draftUsername.isEmpty || draftPassword.isEmpty)
                } else {
                    Button("Edit") { beginEditing() }
                        .disabled(isLocked)
                }
            }
            // Canceling only makes sense once there's an existing connection to cancel back
            // to — with nothing configured yet, Cancel had no real "before" state to return
            // to, and just hid the form behind a blank summary instead.
            if isEditing && isConfigured {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditing = false; testResult = nil }
                }
            }
        }
        .onAppear { if !isConfigured { beginEditing() } }
        .confirmationDialog(
            "Remove Seerr connection?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the saved server URL and credentials. You can reconnect any time.")
        }
    }

    // MARK: - Read-only summary

    @ViewBuilder
    private var connectedSummary: some View {
        Section {
            LabeledContent("Server URL", value: seerrURL)
                .lineLimit(1)
            LabeledContent("Account Type", value: seerrAuthMethod.label)
            LabeledContent("Username", value: seerrUsername)
        } header: {
            Label("Connection", systemImage: "server.rack")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }

        Section {
            Button(role: .destructive) { showRemoveConfirm = true } label: {
                Text("Remove Connection")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Editing form

    @ViewBuilder
    private var editingForm: some View {
        // Server URL
        Section {
            TextField("http://10.0.1.122:5055", text: $draftURL)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
        } header: {
            Label("Server URL", systemImage: "server.rack")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }

        // Account type picker
        Section {
            Picker("Account Type", selection: $draftAuthMethod) {
                ForEach(SeerrAuthMethod.allCases, id: \.self) { method in
                    Text(method.label).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Label("Account Type", systemImage: "person.badge.key")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        } footer: {
            Text(draftAuthMethod.description)
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }

        // Credentials
        Section {
            TextField("Username", text: $draftUsername)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            SecureField("Password", text: $draftPassword)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        } header: {
            Label("Credentials", systemImage: "person.fill")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }

        // Test connection
        Section {
            Button { testConnection() } label: {
                HStack {
                    if isTesting { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "network") }
                    Text(isTesting ? "Testing…" : "Test Connection")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(draftURL.isEmpty || draftUsername.isEmpty || draftPassword.isEmpty || isTesting)

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("✓") ? DT.Color.palette("10b981") : DT.Color.palette("EF4444"))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Actions

    private func beginEditing() {
        draftURL = seerrURL
        draftUsername = seerrUsername
        draftPassword = authManager.seerrPassword
        draftAuthMethod = seerrAuthMethod
        testResult = nil
        isEditing = true
    }

    private func save() {
        seerrURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        seerrUsername = draftUsername
        authManager.saveSeerrPassword(draftPassword)
        seerrAuthMethod = draftAuthMethod
        isEditing = false
    }

    private func remove() {
        seerrURL = ""; seerrUsername = ""
        authManager.removeSeerrPassword()
        seerrAuthMethod = .jellyfin
        seerrRepo.clearAuthFailure()
        beginEditing()
    }

    private func testConnection() {
        guard let url = URL(string: draftURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            testResult = "✗ Invalid URL"; return
        }
        isTesting = true; testResult = nil
        let path = draftAuthMethod.apiPath
        let body = try? JSONSerialization.data(withJSONObject: [
            "username": draftUsername,
            "password": draftPassword,
        ])
        Task {
            var req = URLRequest(url: url.appendingPathComponent(path))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 10
            do {
                let (_, resp) = try await URLSession.arcfin.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    testResult = "✓ Connected as \(draftAuthMethod.label)"
                    seerrRepo.clearAuthFailure()
                } else if let http = resp as? HTTPURLResponse, http.statusCode == 403 {
                    testResult = "✗ Wrong account type — try the other option"
                } else {
                    testResult = "✗ Invalid credentials"
                }
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

// MARK: - tvOS users sheet

#if os(tvOS)
struct TVUsersView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var pinStates: [UUID: Bool] = [:]
    @State private var pinTask: TVPINTask?

    private var activeID: UUID? { authManager.state.credential?.id }

    private var otherProfiles: [ServerCredential] {
        authManager.profiles.filter { $0.id != activeID }
    }

    var body: some View {
        List {
            if let active = authManager.state.credential {
                Section {
                    tvProfileRow(active, isActive: true)
                        .listRowBackground(Color.clear)
                        .focusEffectDisabled()
                    if pinStates[active.id] == true {
                        Button("Change PIN") { pinTask = TVPINTask(profile: active, kind: .change) }
                            .tvListRow()
                        Button("Remove PIN") { pinTask = TVPINTask(profile: active, kind: .remove) }
                            .tvListRow()
                    } else {
                        Button("Set a PIN") { pinTask = TVPINTask(profile: active, kind: .set) }
                            .tvListRow()
                    }
                } header: { sectionLabel("Current Profile") } footer: {
                    Text("With a PIN, Arcfin asks for it when it opens and before switching to this profile.")
                }
            }

            if !otherProfiles.isEmpty {
                Section {
                    ForEach(otherProfiles) { profile in
                        Button {
                            if pinStates[profile.id] == true {
                                pinTask = TVPINTask(profile: profile, kind: .unlock)
                            } else {
                                authManager.switchTo(profile)
                                dismiss()
                            }
                        } label: {
                            tvProfileRow(profile, isActive: false)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: { sectionLabel("Switch To") }
            }

            Section {
                NavigationLink {
                    TVAddProfileFlowView(onProfileAdded: { dismiss() })
                } label: {
                    Text("Add Profile")
                        .foregroundStyle(DT.Color.accent)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 48, bottom: 8, trailing: 48))
            }

            Section {
                Button(role: .destructive) {
                    authManager.signOut()
                    dismiss()
                } label: {
                    Text("Sign Out")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .screenBackground()
        .navigationTitle("Profiles")
        .task { await loadPINStates() }
        .fullScreenCover(item: $pinTask) { task in
            TVPINFlow(task: task) { switched in
                pinTask = nil
                Task { await loadPINStates() }
                if switched { dismiss() }
            }
        }
    }

    private func loadPINStates() async {
        var states: [UUID: Bool] = [:]
        for profile in authManager.profiles {
            states[profile.id] = await authManager.pin(for: profile.id) != nil
        }
        pinStates = states
    }

    private func tvProfileRow(_ cred: ServerCredential, isActive: Bool) -> some View {
        let initials = cred.displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()

        return HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [DT.Color.accent, DT.Color.accentDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 52 * DT.Scale.font, height: 52 * DT.Scale.font)
                    .shadow(color: isActive ? DT.Color.accent.opacity(0.4) : .clear, radius: 8)
                Text(initials)
                    .scaledFont(size: 18, weight: .bold, design: .rounded)
                    .foregroundStyle(DT.Color.onAccent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cred.displayName)
                    .scaledFont(size: 18, weight: .semibold)
                Text(cred.baseURL.host ?? cred.baseURL.absoluteString)
                    .scaledFont(size: 14)
                    .opacity(0.6)
                    .lineLimit(1)
            }

            Spacer()

            if pinStates[cred.id] == true {
                Image(systemName: "lock.fill")
                    .scaledFont(size: 18)
                    .opacity(0.6)
                    .accessibilityLabel("PIN protected")
            }
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .scaledFont(size: 26)
                    .foregroundStyle(DT.Color.accent)
            }
        }
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
    }
}

// MARK: - tvOS PINs

struct TVPINTask: Identifiable {
    enum Kind { case set, change, remove, unlock }
    let id = UUID()
    let profile: ServerCredential
    let kind: Kind
}

/// Setting, changing and removing a profile's PIN, and entering it to switch to that profile.
private struct TVPINFlow: View {
    let task: TVPINTask
    /// True when the flow ended by switching to the profile.
    let onDone: (Bool) -> Void

    @Environment(AuthManager.self) private var authManager
    @State private var storedPIN: String?
    @State private var verified = false
    @State private var firstEntry: String?
    @State private var errorMessage: String?
    @State private var resetToken = 0

    private var title: String {
        switch task.kind {
        case .unlock: String(localized: "Enter PIN")
        case .remove: String(localized: "Enter PIN to remove it")
        case .change where !verified: String(localized: "Enter current PIN")
        case .set, .change: firstEntry == nil ? String(localized: "Enter a new PIN") : String(localized: "Confirm the PIN")
        }
    }

    var body: some View {
        PINPadView(
            title: title,
            subtitle: task.profile.displayName,
            errorMessage: errorMessage,
            resetToken: resetToken,
            onCancel: { onDone(false) },
            onComplete: handle
        )
        .id(title)
        .task { storedPIN = await authManager.pin(for: task.profile.id) }
    }

    private func handle(_ entered: String) {
        let needsCurrent = task.kind == .unlock || task.kind == .remove || (task.kind == .change && !verified)
        if needsCurrent {
            guard entered == storedPIN else { return fail("Incorrect PIN") }
            errorMessage = nil
            switch task.kind {
            case .unlock:
                authManager.switchTo(task.profile)
                onDone(true)
            case .remove:
                authManager.removePin(for: task.profile.id)
                onDone(false)
            default:
                verified = true
            }
            return
        }
        guard let first = firstEntry else {
            firstEntry = entered
            errorMessage = nil
            return
        }
        guard entered == first else {
            firstEntry = nil
            return fail("PINs don't match")
        }
        authManager.savePin(entered, for: task.profile.id)
        onDone(false)
    }

    private func fail(_ message: String) {
        errorMessage = message
        resetToken += 1
    }
}

// MARK: - tvOS add-profile flow (pushed within TVUsersView's NavigationStack)

private struct TVAddProfileFlowView: View {
    var onProfileAdded: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let cred = authManager.state.credential {
            AuthView(
                serverURL: cred.baseURL,
                serverName: cred.baseURL.host ?? cred.baseURL.absoluteString,
                onBack: { dismiss() },
                onAuthenticated: { credential in
                    authManager.addProfile(credential)
                    onProfileAdded()
                }
            )
            .navigationTitle("Add Profile")
        }
    }
}
#endif

/// An in-app choice writes AppleLanguages into Arcfin's own defaults, the same key the
/// system's per-app language setting uses; Foundation reads it at launch.
private enum AppLanguage {
    private static let key = "AppleLanguages"

    static let available = Bundle.main.localizations
        .filter { $0 != "Base" }
        .sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }

    static var isChoosable: Bool { available.count > 1 }

    /// The choice this launch is running with, so a change can say it applies next time.
    static let atLaunch = override ?? ""

    static var override: String? {
        get {
            let domain = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:))
            return (domain?[key] as? [String])?.first.flatMap { available.contains($0) ? $0 : nil }
        }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// Each language in its own words, as language pickers show them.
    static func name(of code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
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

