import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine
import Persistence
import SeerrAPI

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var showUsersSheet = false
    @State private var quickConnectCode = ""
    @State private var isAuthorizingQC = false
    @State private var quickConnectResult: String?
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
    @AppStorage("streamystatsURL")     private var streamystatsURL      = ""

    var body: some View {
        List {
            profileSection

#if os(tvOS)
            // ── Quick Connect ────────────────────────────────────────────
            Section {
                HStack(spacing: 10) {
                    TextField("Code", text: $quickConnectCode)
                        .autocorrectionDisabled()
                    Button {
                        authorizeQuickConnect()
                    } label: {
                        if isAuthorizingQC { ProgressView().scaleEffect(0.8) }
                        else { Text("Authorize") }
                    }
                    .disabled(quickConnectCode.isEmpty || isAuthorizingQC)
                }
                if let quickConnectResult {
                    Text(quickConnectResult)
                        .font(.caption)
                        .foregroundStyle(quickConnectResult.hasPrefix("✓") ? Color(hex: "10b981") : Color(hex: "EF4444"))
                }
            } header: {
                sectionHeader("Quick Connect", icon: "qrcode")
            } footer: {
                Text("Enter the code shown on another device to sign it in instantly using this account.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

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
                NavigationLink {
                    NotificationsSettingsView()
                } label: {
                    settingsRow("Notifications", icon: "bell")
                }
                .listRowBackground(Color.clear)
            } header: {
                sectionHeader("Preferences", icon: "slider.horizontal.3")
            }

            // ── Account & Server ─────────────────────────────────────────
            Section {
                serverRow
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
                Toggle("Show Discover on Home", isOn: $seerrDiscoverEnabled)
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
                    StreamystatsPluginView()
                } label: {
                    HStack {
                        Text("Streamystats")
                        Spacer()
                        if !streamystatsURL.isEmpty {
                            Text("Connected").font(.caption2).foregroundStyle(Color(hex: "10b981"))
                        }
                    }
                }
                .listRowBackground(Color.clear)
            } header: {
                sectionHeader("Plugins", icon: "puzzlepiece.extension")
            }
#else
            // Grouped hub — each row below pushes to its own focused screen instead of
            // stacking every preference into one long page.
            Section {
                NavigationLink {
                    PlaybackSettingsView()
                } label: {
                    settingsRow("Playback", icon: "play.circle")
                }
                // Downloads aren't wired up on macOS — DownloadManager's UI entry points are
                // iOS-only, so this row would push to a screen with nothing it can actually do.
                #if os(iOS)
                NavigationLink {
                    DownloadsSettingsView()
                } label: {
                    settingsRow("Downloads", icon: "arrow.down.circle")
                }
                #endif
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
                LabeledContent("Privacy Policy", value: "arcfin.psmattas.com/privacy")
                    .listRowBackground(Color.clear)
                LabeledContent("Terms of Use", value: "arcfin.psmattas.com/terms")
                    .listRowBackground(Color.clear)
                LabeledContent("Data Protection", value: "arcfin.psmattas.com/data-protection")
                    .listRowBackground(Color.clear)
#else
                Link(destination: URL(string: "https://arcfin.psmattas.com/privacy")!) {
                    HStack {
                        Text("Privacy Policy").foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(DT.Color.textSecondary)
                    }
                }
                Link(destination: URL(string: "https://arcfin.psmattas.com/terms")!) {
                    HStack {
                        Text("Terms of Use").foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(DT.Color.textSecondary)
                    }
                }
                Link(destination: URL(string: "https://arcfin.psmattas.com/data-protection")!) {
                    HStack {
                        Text("Data Protection").foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(DT.Color.textSecondary)
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
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.6))
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
        .background(DT.Color.backgroundPrimary)
#if os(tvOS)
        .navigationTitle(authManager.state.credential?.displayName ?? "Profile")
        .id(listID)
        .onAppear { listID = UUID() }
        .sheet(isPresented: $showUsersSheet) {
            NavigationStack { TVUsersView() }
                .frame(minWidth: 900)
                .preferredColorScheme(.dark)
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
                .preferredColorScheme(.dark)
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
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .arcfinRowSeparatorHidden()
#endif
            }
        }
    }

    private func initialsLabel(_ initials: String) -> some View {
        Text(initials)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }

    private func settingsRow(_ title: String, icon: String) -> some View {
        Label {
            Text(title).foregroundStyle(DT.Color.textPrimary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(DT.Color.accent)
                .frame(width: 22)
        }
    }

    private func profileCard(cred: ServerCredential) -> some View {
        let initials = cred.displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()

        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [DT.Color.accent, DT.Color.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 52, height: 52)
                    .shadow(color: DT.Color.accent.opacity(0.35), radius: 10, y: 3)
                if let tag = cred.userImageTag {
                    AsyncImage(url: JellyfinMediaClient.userImageURL(baseURL: cred.baseURL, userID: cred.userID, tag: tag, fillWidth: 104, token: cred.accessToken)) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: initialsLabel(initials)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                } else {
                    initialsLabel(initials)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(cred.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 10))
                        .foregroundStyle(DT.Color.textSecondary)
                    Text(cred.baseURL.host ?? cred.baseURL.absoluteString)
                        .font(.system(size: 13))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .fill(DT.Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.lg)
                        .stroke(DT.Color.accent.opacity(0.18), lineWidth: 1)
                )
        )
        .padding(.horizontal, DT.Spacing.pagePad)
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
            Text("Auth Failed").font(.caption2).foregroundStyle(Color(hex: "EF4444"))
        } else if !seerrURL.isEmpty {
            Text("Connected").font(.caption2).foregroundStyle(Color(hex: "10b981"))
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12 * DT.Scale.font, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
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

    // MARK: - Quick Connect

    private func authorizeQuickConnect() {
        guard case .authenticated(let cred) = authManager.state else { return }
        isAuthorizingQC = true
        quickConnectResult = nil
        let code = quickConnectCode
        Task {
            let header = authManager.authClient.authHeader(token: cred.accessToken)
            do {
                let ok = try await authManager.authClient.authorizeQuickConnect(
                    baseURL: cred.baseURL, authHeader: header, code: code
                )
                quickConnectResult = ok ? "✓ Device authorized" : "✗ Invalid or expired code"
                if ok { quickConnectCode = "" }
            } catch {
                quickConnectResult = "✗ \(error.localizedDescription)"
            }
            isAuthorizingQC = false
        }
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
        case .max:   "Max Quality"
        case .auto:  "Auto (Recommended)"
        case .p4k:   "4K Ultra HD"
        case .p1080: "1080p HD"
        case .p720:  "720p"
        case .p480:  "480p"
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

    @AppStorage("seerrURL")         private var seerrURL        = ""
    @AppStorage("seerrUsername")    private var seerrUsername   = ""
    @AppStorage("seerrPassword")    private var seerrPassword   = ""
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

    var body: some View {
        List {
            if isEditing {
                editingForm
            } else {
                connectedSummary
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Seerr")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isEditing {
                    Button("Save") { save() }
                        .disabled(draftURL.isEmpty || draftUsername.isEmpty || draftPassword.isEmpty)
                } else {
                    Button("Edit") { beginEditing() }
                }
            }
            if isEditing {
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
                .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 12, weight: .semibold))
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
                    .foregroundStyle(result.hasPrefix("✓") ? Color(hex: "10b981") : Color(hex: "EF4444"))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Actions

    private func beginEditing() {
        draftURL = seerrURL
        draftUsername = seerrUsername
        draftPassword = seerrPassword
        draftAuthMethod = seerrAuthMethod
        testResult = nil
        isEditing = true
    }

    private func save() {
        seerrURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        seerrUsername = draftUsername
        seerrPassword = draftPassword
        seerrAuthMethod = draftAuthMethod
        isEditing = false
    }

    private func remove() {
        seerrURL = ""; seerrUsername = ""; seerrPassword = ""
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
                let (_, resp) = try await URLSession.shared.data(for: req)
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

// MARK: - Streamystats plugin view

struct StreamystatsPluginView: View {
    @AppStorage("streamystatsURL") private var streamystatsURL = ""
    @State private var testResult: String? = nil
    @State private var isTesting = false

    var body: some View {
        List {
            Section {
                TextField("https://stats.example.com", text: $streamystatsURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            } header: {
                Label("Server URL", systemImage: "server.rack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Streamystats authenticates using your existing Jellyfin session — no separate credentials needed.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "Testing…" : "Test Connection")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(streamystatsURL.isEmpty || isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? Color(hex: "10b981") : Color(hex: "EF4444"))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Streamystats")
    }

    private func testConnection() {
        guard let url = URL(string: streamystatsURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            testResult = "✗ Invalid URL"; return
        }
        isTesting = true; testResult = nil
        Task {
            // Public health endpoint — no auth needed
            let req = URLRequest(url: url.appendingPathComponent("api/health"))
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    testResult = "✓ Server reachable"
                } else {
                    testResult = "✗ Server returned an error"
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
                } header: { sectionLabel("Current Profile") }
            }

            if !otherProfiles.isEmpty {
                Section {
                    ForEach(otherProfiles) { profile in
                        Button {
                            authManager.switchTo(profile)
                            dismiss()
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
        .background(DT.Color.backgroundPrimary)
        .navigationTitle("Profiles")
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
                    .font(.system(size: 18 * DT.Scale.font, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cred.displayName)
                    .font(.system(size: 18 * DT.Scale.font, weight: .semibold))
                Text(cred.baseURL.host ?? cred.baseURL.absoluteString)
                    .font(.system(size: 14 * DT.Scale.font))
                    .opacity(0.6)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26 * DT.Scale.font))
                    .foregroundStyle(DT.Color.accent)
            }
        }
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
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

