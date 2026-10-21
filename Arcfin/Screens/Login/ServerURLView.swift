// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

struct ServerURLView: View {
    var onConnected: (URL, String) -> Void
    /// nil for the very first login (nothing to go back to) — set when this screen is
    /// reached from Settings > Add Server, where the system nav bar is hidden and this was
    /// the only step of that flow with no way back at all.
    var onBack: (() -> Void)? = nil

    @Environment(AuthManager.self) private var authManager

    @State private var serverURL: String = ""
    @State private var connecting: Bool = false
    @State private var connected: Bool = false
    @State private var showCustomHeaders = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var discoveredServers: [DiscoveredServer] = []
    @State private var discovering: Bool = false
    @State private var recentServers: [ServerCredential] = []
    @State private var showSetupGuide: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let onBack {
                    HStack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .scaledFont(size: 12, weight: .semibold)
                                Text("Back").font(DT.Font.caption)
                            }
                            .foregroundStyle(DT.Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.top, 12)
                }

                stepIndicator

                ArcfinLogoView(size: 52)
                    .padding(.top, 24)

                VStack(spacing: 4) {
                    Text("Connect to Server")
                        .font(DT.Font.sectionTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                        .tracking(-0.6)

                    Text("Enter your Jellyfin server address to get started")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.top, 20)
                .padding(.horizontal, DT.Spacing.pagePad)

                // URL field
                VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                    fieldLabel("Server Address")

                    glassTextField(
                        text: $serverURL,
                        placeholder: "https://jellyfin.example.com",
                        leadingIcon: "globe",
                        trailingCheckmark: connected
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.md)
                            .stroke(
                                showError ? Color.red.opacity(0.5) :
                                connected ? DT.Color.accent.opacity(0.4) :
                                Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                    .onChange(of: serverURL) {
                        showError = false
                        connected = false
                    }
                    .onSubmit { Task { await handleConnect() } }

                    if showError {
                        Text(errorMessage)
                            .font(DT.Font.caption2)
                            .foregroundStyle(.red)
                            .padding(.leading, 2)
                    }

                    Button { showCustomHeaders = true } label: {
                        Label("Custom Headers", systemImage: "key.horizontal")
                            .font(DT.Font.caption2)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                    .accessibilityHint("For a server behind an access gateway")
                }
                .padding(.top, DT.Spacing.lg)
                .padding(.horizontal, DT.Spacing.pagePad)

                // Local discovery results
                if discovering || !discoveredServers.isEmpty {
                    VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                        HStack {
                            fieldLabel("Found on network")
                            Spacer()
                            if discovering {
                                ProgressView().scaleEffect(0.7).tint(DT.Color.accent)
                            }
                        }

                        if discoveredServers.isEmpty {
                            Text("Searching your local network…")
                                .font(DT.Font.caption2)
                                .foregroundStyle(DT.Color.textSecondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(discoveredServers) { server in
                                serverRow(
                                    icon: "wifi",
                                    title: server.name,
                                    subtitle: server.address
                                ) { serverURL = server.address; showError = false; connected = false }
                            }
                        }
                    }
                    .padding(.top, DT.Spacing.sm)
                    .padding(.horizontal, DT.Spacing.pagePad)
                }

                // Recent servers from keychain
                if !recentServers.isEmpty {
                    VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                        fieldLabel("Recent Servers")
                        ForEach(recentServers) { cred in
                            serverRow(
                                icon: "server.rack",
                                title: cred.displayName,
                                subtitle: cred.baseURL.absoluteString
                            ) { serverURL = cred.baseURL.absoluteString; showError = false; connected = false }
                        }
                    }
                    .padding(.top, DT.Spacing.sm)
                    .padding(.horizontal, DT.Spacing.pagePad)
                }

                // Connect button — Liquid Glass
                Button { Task { await handleConnect() } } label: {
                    ZStack {
                        if connecting {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white).scaleEffect(0.85)
                                Text("Connecting…").font(DT.Font.button).foregroundStyle(.white.opacity(0.8))
                            }
                        } else {
                            Text("Connect").font(DT.Font.button).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .glassEffect(
                    connecting ? .regular : .regular.tint(DT.Color.accent).interactive(),
                    in: .rect(cornerRadius: DT.Radius.lg)
                )
                .disabled(connecting)
                .padding(.top, DT.Spacing.lg)
                .padding(.horizontal, DT.Spacing.pagePad)

                HStack(spacing: 4) {
                    Text("Need help?").font(DT.Font.caption).foregroundStyle(DT.Color.textSecondary)
                    Button { showSetupGuide = true } label: {
                        Text("Setup guide").font(DT.Font.caption).foregroundStyle(.white).fontWeight(.medium)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                    }
                    .glassEffect(.regular.tint(DT.Color.accent).interactive(), in: .capsule)
                }
                .padding(.top, DT.Spacing.md)
            }
            .padding(.top, 52)
            .padding(.bottom, DT.Spacing.xxxl)
            #if os(macOS)
            // Nothing here constrained content width, so every field/button stretched to
            // the full ~1280pt default window width — a phone-width login form blown up
            // that wide doesn't just look big, it looks broken. Real macOS sign-in panels
            // (Mail, System Settings' account setup, etc.) are narrow and centered even in
            // a much wider window; capping then re-expanding-to-center is the standard
            // SwiftUI idiom for that.
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            #endif
        }
        .task { await runDiscovery() }
        .sheet(isPresented: $showSetupGuide) { SetupGuideSheet() }
        .sheet(isPresented: $showCustomHeaders) {
            NavigationStack {
                CustomHeadersView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showCustomHeaders = false } }
                    }
            }
        }
    }

    // MARK: - Subviews

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            Capsule().fill(DT.Color.accent).frame(width: 20, height: 6)
            Capsule().fill(.white.opacity(0.15)).frame(width: 6, height: 6)
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .scaledFont(size: 10, weight: .bold)
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(DT.Color.textSecondary)
    }

    private func glassTextField(text: Binding<String>, placeholder: String, leadingIcon: String, trailingCheckmark: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: leadingIcon).font(.system(.footnote)).foregroundStyle(DT.Color.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textPrimary)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            if trailingCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(.subheadline))
                    .foregroundStyle(Color(hex: "10b981"))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .arcfinFieldBackground()
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
        .animation(DT.Animation.fast, value: trailingCheckmark)
    }

    private func serverRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DT.Color.accent.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DT.Color.accent.opacity(0.15), lineWidth: 1))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon).font(.system(.caption2)).foregroundStyle(DT.Color.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).scaledFont(size: 11, weight: .medium).foregroundStyle(DT.Color.textPrimary).lineLimit(1)
                    Text(subtitle).font(DT.Font.caption2).foregroundStyle(DT.Color.textSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(.caption2)).foregroundStyle(DT.Color.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .tvFocusRing(cornerRadius: 10)
        .padding(.bottom, 6)
    }

    // MARK: - Actions

    private func runDiscovery() async {
        // Load from keychain off main thread, then start UDP discovery in parallel
        async let stored = authManager.fetchStoredServers()
        async let found = ServerDiscovery.discover(timeout: 3.0)
        discovering = true
        recentServers = await stored
        discoveredServers = await found
        discovering = false
    }

    private func handleConnect() async {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError = true; errorMessage = "Please enter a server address."; return
        }
        connecting = true
        showError = false
        do {
            let (url, name) = try await authManager.authClient.validateServer(url: trimmed)
            connected = true
            try? await Task.sleep(for: .milliseconds(600))
            connecting = false
            onConnected(url, name)
        } catch {
            connecting = false
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ZStack {
        DT.Color.backgroundPrimary.ignoresSafeArea()
        ServerURLView(onConnected: { _, _ in })
            .environment(AuthManager())
    }
}
