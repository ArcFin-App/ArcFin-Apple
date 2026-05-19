import SwiftUI
import AuthCore
import JellyseerrAPI

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(JellyseerrRepository.self) private var seerrRepo

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

            // ── Account & Server ─────────────────────────────────────────
            Section {
                serverRow
                NavigationLink {
                    placeholderDetail("Switch Server")
                } label: {
#if os(tvOS)
                    TVFocusRowLabel { Label("Switch Server", systemImage: "server.rack") }
#else
                    Label("Switch Server", systemImage: "server.rack")
#endif
                }
                .tvListRow()
                NavigationLink {
                    placeholderDetail("Add Server")
                } label: {
#if os(tvOS)
                    TVFocusRowLabel { Label("Add Server", systemImage: "plus.circle") }
#else
                    Label("Add Server", systemImage: "plus.circle")
#endif
                }
                .tvListRow()
            } header: {
                sectionHeader("Account & Server", icon: "person.badge.key")
            }

            // ── Plugins ──────────────────────────────────────────────────
            Section {
                Toggle("Show Discover on Home", isOn: $seerrDiscoverEnabled)
                NavigationLink {
                    JellyseerrPluginView()
#if !os(tvOS)
                        .toolbar(.hidden, for: .tabBar)
#endif
                } label: {
#if os(tvOS)
                    TVFocusRowLabel {
                        HStack {
                            Label("Jellyseerr", systemImage: "clock.fill")
                            Spacer()
                            seerrStatusPill
                        }
                    }
#else
                    HStack {
                        Label("Jellyseerr", systemImage: "clock.fill")
                        Spacer()
                        seerrStatusPill
                    }
#endif
                }
                .tvListRow()
                NavigationLink {
                    StreamystatsPluginView()
#if !os(tvOS)
                        .toolbar(.hidden, for: .tabBar)
#endif
                } label: {
#if os(tvOS)
                    TVFocusRowLabel {
                        HStack {
                            Label("Streamystats", systemImage: "chart.xyaxis.line")
                            Spacer()
                            if !streamystatsURL.isEmpty {
                                Text("Connected").font(.caption2).foregroundStyle(Color(hex: "10b981"))
                            }
                        }
                    }
#else
                    HStack {
                        Label("Streamystats", systemImage: "chart.xyaxis.line")
                        Spacer()
                        if !streamystatsURL.isEmpty {
                            Text("Connected").font(.caption2).foregroundStyle(Color(hex: "10b981"))
                        }
                    }
#endif
                }
                .tvListRow()
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
                Link(destination: URL(string: "https://jellyfin.org")!) {
#if os(tvOS)
                    TVFocusRowLabel { Label("Jellyfin Website", systemImage: "safari") }
#else
                    Label("Jellyfin Website", systemImage: "safari")
#endif
                }
                .tvListRow()
                NavigationLink {
                    placeholderDetail("Open Source Licenses")
                } label: {
#if os(tvOS)
                    TVFocusRowLabel { Label("Open Source Licenses", systemImage: "doc.text") }
#else
                    Label("Open Source Licenses", systemImage: "doc.text")
#endif
                }
                .tvListRow()
            } header: {
                sectionHeader("About", icon: "info.circle")
            }

            // ── Sign Out ─────────────────────────────────────────────────
            Section {
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
#if os(tvOS)
                    TVFocusRowLabel {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundStyle(.red)
                    }
#else
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .center)
#endif
                }
                .tvListRow()
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Settings")
#if !os(tvOS)
        .toolbar(.hidden, for: .tabBar)
#endif
    }

    // MARK: - Profile section

    @ViewBuilder
    private var profileSection: some View {
        if case .authenticated(let cred) = authManager.state {
            Section {
                profileCard(cred: cred)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .arcfinRowSeparatorHidden()
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
                    .fill(
                        LinearGradient(
                            colors: [DT.Color.accent, DT.Color.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: DT.Color.accent.opacity(0.4), radius: 12, y: 4)
                Text(initials)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cred.displayName)
                    .font(.system(size: 18, weight: .semibold))
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
        .padding(.vertical, 16)
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
            .font(.system(size: 12, weight: .semibold))
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

// MARK: - Jellyseerr plugin view

struct JellyseerrPluginView: View {
    @AppStorage("seerrURL")         private var seerrURL        = ""
    @AppStorage("seerrUsername")    private var seerrUsername   = ""
    @AppStorage("seerrPassword")    private var seerrPassword   = ""
    @AppStorage("seerrAuthMethod")  private var seerrAuthMethod = JellyseerrAuthMethod.jellyfin

    @State private var testResult: String? = nil
    @State private var isTesting = false

    var body: some View {
        List {
            // Server URL
            Section {
                TextField("http://10.0.1.122:5055", text: $seerrURL)
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
                Picker("Account Type", selection: $seerrAuthMethod) {
                    ForEach(JellyseerrAuthMethod.allCases, id: \.self) { method in
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
                Text(seerrAuthMethod.description)
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            // Credentials
            Section {
                TextField("Username", text: $seerrUsername)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $seerrPassword)
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
                .disabled(seerrURL.isEmpty || seerrUsername.isEmpty || seerrPassword.isEmpty || isTesting)

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
        .arcfinNavTitleLarge("Jellyseerr")
    }

    private func testConnection() {
        guard let url = URL(string: seerrURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            testResult = "✗ Invalid URL"; return
        }
        isTesting = true; testResult = nil
        let path = seerrAuthMethod.apiPath
        let body = try? JSONSerialization.data(withJSONObject: [
            "username": seerrUsername,
            "password": seerrPassword,
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
                    testResult = "✓ Connected as \(seerrAuthMethod.label)"
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

