import SwiftUI
import AuthCore
import SeerrAPI

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.openURL) private var openURL

    @State private var showUsersSheet = false
    #if !os(tvOS)
    @State private var usersDetent: PresentationDetent = .medium
    #endif
    #if os(tvOS)
    @State private var listID = UUID()
    #endif

    // MARK: - Persisted preferences

    @AppStorage("videoQuality")       private var videoQuality    = VideoQuality.auto
    @AppStorage("autoPlayNext")       private var autoPlayNext    = true
    @AppStorage("skipIntro")          private var skipIntro       = false
    @AppStorage("skipCredits")        private var skipCredits     = false
    @AppStorage("subtitleDefault")    private var subtitleDefault = false

    @AppStorage("wifiOnly")           private var wifiOnly          = true
    @AppStorage("downloadQuality")    private var downloadQuality   = VideoQuality.p1080

    @AppStorage("notifyNewContent")   private var notifyNewContent  = true
    @AppStorage("notifyDownload")     private var notifyDownload    = true

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("seerrURL")            private var seerrURL             = ""
    @AppStorage("streamystatsURL")     private var streamystatsURL      = ""

    var body: some View {
        List {
            profileSection

            // ── Playback ─────────────────────────────────────────────────
            Section {
                Picker("Video Quality", selection: $videoQuality) {
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                Toggle("Auto-play Next Episode", isOn: $autoPlayNext)
                Toggle("Skip Intro Automatically", isOn: $skipIntro)
                Toggle("Skip Credits Automatically", isOn: $skipCredits)
                Toggle("Show Subtitles by Default", isOn: $subtitleDefault)
            } header: {
                sectionHeader("Playback", icon: "play.circle")
            }

            // ── Downloads ────────────────────────────────────────────────
            Section {
                Toggle("Wi-Fi Only", isOn: $wifiOnly)
                Picker("Download Quality", selection: $downloadQuality) {
                    ForEach(VideoQuality.allCases.filter { $0 != .auto }) { q in
                        Text(q.label).tag(q)
                    }
                }
            } header: {
                sectionHeader("Downloads", icon: "arrow.down.circle")
            }

            // ── Notifications ────────────────────────────────────────────
            Section {
                Toggle("New Content Added", isOn: $notifyNewContent)
                Toggle("Download Complete", isOn: $notifyDownload)
            } header: {
                sectionHeader("Notifications", icon: "bell")
            }

            // ── Appearance ───────────────────────────────────────────────
#if !os(tvOS)
            Section {
                NavigationLink {
                    AppearanceView()
                } label: {
                    Text("Appearance")
                }
            } header: {
                sectionHeader("Appearance", icon: "paintbrush")
            }
#endif

            // ── Account & Server ─────────────────────────────────────────
            Section {
                serverRow
                NavigationLink {
                    placeholderDetail("Switch Server")
                } label: {
                    Text("Switch Server")
                }
#if os(tvOS)
                .listRowBackground(Color.clear)
#endif
                NavigationLink {
                    placeholderDetail("Add Server")
                } label: {
                    Text("Add Server")
                }
#if os(tvOS)
                .listRowBackground(Color.clear)
#endif
            } header: {
                sectionHeader("Account & Server", icon: "person.badge.key")
            }

            // ── Plugins ──────────────────────────────────────────────────
            Section {
                Toggle("Show Discover on Home", isOn: $seerrDiscoverEnabled)
                NavigationLink {
                    SeerrPluginView()
#if !os(tvOS)
                        .toolbar(.hidden, for: .tabBar)
#endif
                } label: {
                    HStack {
                        Text("Seerr")
                        Spacer()
                        seerrStatusPill
                    }
                }
#if os(tvOS)
                .listRowBackground(Color.clear)
#endif
                NavigationLink {
                    StreamystatsPluginView()
#if !os(tvOS)
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
#if os(tvOS)
                .listRowBackground(Color.clear)
#endif
            } header: {
                sectionHeader("Plugins", icon: "puzzlepiece.extension")
            }

            // ── About ────────────────────────────────────────────────────
            Section {
                LabeledContent("Version") {
                    Text(appVersion).foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(buildNumber).foregroundStyle(.secondary)
                }
#if !os(tvOS)
                Button {
                    openURL(URL(string: "https://jellyfin.org")!)
                } label: {
                    Text("Jellyfin Website")
                }
#endif
                NavigationLink {
                    placeholderDetail("Open Source Licenses")
                } label: {
                    Text("Open Source Licenses")
                }
#if os(tvOS)
                .listRowBackground(Color.clear)
#endif
            } header: {
                sectionHeader("About", icon: "info.circle")
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
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
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
                    .frame(width: 64, height: 64)
                    .shadow(color: DT.Color.accent.opacity(0.4), radius: 12, y: 4)
                Text(initials)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cred.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.accent)
                    Text(cred.baseURL.host ?? cred.baseURL.absoluteString)
                        .font(.system(size: 13))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "10b981"))
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "10b981"))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
#if !os(tvOS)
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
    case auto, p4k = "4K", p1080 = "1080p", p720 = "720p", p480 = "480p"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto:  "Auto (Recommended)"
        case .p4k:   "4K Ultra HD"
        case .p1080: "1080p HD"
        case .p720:  "720p"
        case .p480:  "480p"
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
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
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
                .textInputAutocapitalization(.never)
            SecureField("Password", text: $draftPassword)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
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
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
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

