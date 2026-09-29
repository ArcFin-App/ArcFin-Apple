// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

private enum AuthMode { case quickConnect, credentials }

struct AuthView: View {
    let serverURL: URL
    let serverName: String
    var onBack: () -> Void
    var onAuthenticated: ((ServerCredential) -> Void)? = nil

    @Environment(AuthManager.self) private var authManager

    @State private var mode: AuthMode = .quickConnect

    // Credentials
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var passwordVisible: Bool = false
    @State private var signingIn: Bool = false
    @State private var signedIn: Bool = false
    @State private var authError: String? = nil

    // Quick Connect
    @State private var qcCode: String = ""
    @State private var qcSecret: String? = nil
    @State private var qcLoading: Bool = false
    @State private var qcPolling: Bool = false

    var body: some View {
        if signedIn {
            successView
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    stepIndicator

                    ArcfinLogoView(size: 52).padding(.top, 24)

                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12 * DT.Scale.font, weight: .semibold))
                                Text(serverName).font(DT.Font.caption)
                            }
                            .foregroundStyle(DT.Color.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 18)

                        Text("Sign In")
                            .font(DT.Font.sectionTitle)
                            .foregroundStyle(DT.Color.textPrimary)
                            .tracking(-0.6)

                        Text(mode == .quickConnect
                             ? "Approve the code on your Jellyfin server"
                             : "Enter your Jellyfin credentials")
                            .font(DT.Font.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                    .padding(.horizontal, DT.Spacing.pagePad)

                    if mode == .quickConnect {
                        quickConnectView
                    } else {
                        credentialsView
                    }

                    if let err = authError {
                        Text(err)
                            .font(DT.Font.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DT.Spacing.pagePad)
                            .padding(.top, DT.Spacing.sm)
                    }
                }
                .padding(.top, 52)
                .padding(.bottom, DT.Spacing.xxxl)
                #if os(macOS)
                // Same fix as ServerURLView — nothing capped content width, so the sign-in
                // form stretched to the full default window width instead of staying a
                // narrow, centered panel the way a real macOS sign-in screen would.
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                #endif
            }
            .animation(DT.Animation.standard, value: mode)
            .task(id: mode) {
                authError = nil
                if mode == .quickConnect {
                    await initiateQC()
                } else {
                    qcPolling = false
                }
            }
            .task(id: qcSecret) {
                guard let secret = qcSecret, qcPolling else { return }
                await pollQuickConnect(secret: secret)
            }
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            Capsule().fill(DT.Color.accent.opacity(0.4)).frame(width: 6, height: 6)
            Capsule().fill(DT.Color.accent).frame(width: 20, height: 6)
        }
    }

    // MARK: - Quick Connect (default)

    private var quickConnectView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How to sign in")
                    .font(.system(size: 11 * DT.Scale.font, weight: .bold))
                    .foregroundStyle(DT.Color.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Open Jellyfin on your browser or another device")
                    Text("2. Go to **Dashboard → Quick Connect**")
                    Text("3. Enter the code below to approve sign-in")
                }
                .font(DT.Font.caption)
                .foregroundStyle(.white.opacity(0.55))
                .lineSpacing(4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DT.Color.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.md).stroke(DT.Color.accent.opacity(0.15), lineWidth: 1))
            .padding(.top, DT.Spacing.md)
            .padding(.horizontal, DT.Spacing.pagePad)

            VStack(spacing: 12) {
                Text("Your Quick Connect Code")
                    .font(.system(size: 10 * DT.Scale.font, weight: .bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DT.Color.textSecondary)

                if qcLoading {
                    ProgressView().tint(DT.Color.accent).padding(.vertical, 10)
                } else if qcCode.isEmpty {
                    Text("—")
                        .font(.system(size: 22 * DT.Scale.font, weight: .heavy, design: .monospaced))
                        .foregroundStyle(DT.Color.textSecondary)
                } else {
                    codeDisplay(qcCode)
                    if qcPolling {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7).tint(DT.Color.accent)
                            Text("Waiting for approval…")
                                .font(DT.Font.caption2)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                }
            }
            .padding(.top, DT.Spacing.lg)
            .padding(.bottom, DT.Spacing.lg)

            Button {
                withAnimation(DT.Animation.fast) { mode = .credentials }
            } label: {
                Text("Sign in with username & password")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .tvFocusRing(cornerRadius: DT.Radius.pill)
        }
    }

    // MARK: - Credentials

    private var credentialsView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Username")
                glassField(icon: "person", placeholder: "jellyfin_user", text: $username, isSecure: false, onSubmit: submitCredentials)
            }
            .padding(.top, DT.Spacing.md)
            .padding(.horizontal, DT.Spacing.pagePad)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Password")
                ZStack(alignment: .trailing) {
                    glassField(icon: "lock", placeholder: "••••••••", text: $password, isSecure: !passwordVisible, onSubmit: submitCredentials)
                    Button { passwordVisible.toggle() } label: {
                        Image(systemName: passwordVisible ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                }
            }
            .padding(.top, DT.Spacing.sm)
            .padding(.horizontal, DT.Spacing.pagePad)

            signInButton(
                label: "Sign In",
                loadingLabel: "Signing in…",
                // Password is deliberately not required here — Jellyfin allows accounts
                // with no password set at all (common for demo/kid profiles), and this
                // button used to block signing into one of those entirely.
                disabled: username.isEmpty
            ) { Task { await handleSignIn() } }
            .padding(.top, DT.Spacing.lg)
            .padding(.horizontal, DT.Spacing.pagePad)

            Button {
                withAnimation(DT.Animation.fast) { mode = .quickConnect }
            } label: {
                Text("Use Quick Connect instead")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .tvFocusRing(cornerRadius: DT.Radius.pill)
            .padding(.top, DT.Spacing.md)
        }
    }

    // MARK: - Code display

    private func codeDisplay(_ code: String) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(code.enumerated()), id: \.offset) { _, ch in
                if ch == " " {
                    Spacer().frame(width: 8)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DT.Color.accent.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.accent.opacity(0.3), lineWidth: 1.5))
                            .frame(width: 36 * DT.Scale.font, height: 46 * DT.Scale.font)
                            .shadow(color: DT.Color.accent.opacity(0.08), radius: 8)
                        Text(String(ch))
                            .font(.system(size: 22 * DT.Scale.font, weight: .heavy, design: .monospaced))
                            .foregroundStyle(DT.Color.accent)
                    }
                }
            }
        }
    }

    // MARK: - Shared sign-in button

    private func signInButton(label: String, loadingLabel: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if signingIn {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white).scaleEffect(0.85)
                        Text(loadingLabel).font(DT.Font.button).foregroundStyle(.white.opacity(0.8))
                    }
                } else {
                    Text(label)
                        .font(DT.Font.button)
                        .foregroundStyle(disabled ? .white.opacity(0.4) : .white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                disabled
                    ? AnyShapeStyle(DT.Color.accent.opacity(0.2))
                    : AnyShapeStyle(LinearGradient(
                        colors: [DT.Color.accentDeep, DT.Color.accent],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                      ))
            )
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            .shadow(color: disabled ? .clear : DT.Color.accent.opacity(0.3), radius: 16)
        }
        .buttonStyle(.plain)
        .disabled(signingIn || disabled)
        .tvFocusRing(cornerRadius: DT.Radius.lg)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10 * DT.Scale.font, weight: .bold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(DT.Color.textSecondary)
    }

    private func glassField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool, onSubmit: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(DT.Color.textSecondary)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(DT.Font.caption).foregroundStyle(DT.Color.textPrimary).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { onSubmit?() }
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(DT.Font.caption).foregroundStyle(DT.Color.textPrimary).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { onSubmit?() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .arcfinFieldBackground()
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.md).stroke(.white.opacity(0.1), lineWidth: 1))
        .tvFocusRing(cornerRadius: DT.Radius.md)
    }

    // MARK: - Success screen

    private var successView: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(DT.Color.accent.opacity(0.12))
                        .overlay(Circle().stroke(DT.Color.accent.opacity(0.5), lineWidth: 1.5))
                        .frame(width: 56, height: 56)
                        .shadow(color: DT.Color.accent.opacity(0.25), radius: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                }
                VStack(spacing: 6) {
                    Text("Welcome, \(authManager.state.displayName)!")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("Opening your library…")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
    }

    // MARK: - Actions

    // Return-key submission (physical keyboard, Mac especially) mirrors the Sign In
    // button's own disabled condition — password stays optional, username doesn't.
    private func submitCredentials() {
        guard !username.isEmpty, !signingIn else { return }
        Task { await handleSignIn() }
    }

    private func handleSignIn() async {
        authError = nil
        signingIn = true
        do {
            let credential = try await authManager.authClient.authenticate(
                baseURL: serverURL, username: username, password: password
            )
            await attemptSeerrAutoLogin(credential: credential, jellyfinPassword: password)
            if let onAuthenticated {
                onAuthenticated(credential)
            } else {
                authManager.save(credential)
                withAnimation { signedIn = true }
            }
        } catch {
            authError = error.localizedDescription
        }
        signingIn = false
    }

    /// If the server's Arcfin Sync plugin has Seerr Account Type locked to "Jellyfin Account",
    /// every user's Seerr login is their Jellyfin login by definition — there's no separate
    /// Seerr credential to ask for. The password just typed is available here for exactly one
    /// use (this one-shot check + prefill) and is never persisted anywhere beyond the same
    /// UserDefaults keys SeerrPluginView already writes to when a user fills that form by hand
    /// — this doesn't lower the bar, it automates what the user would otherwise type in
    /// themselves. Quick Connect sign-in never has a password at all, so it can't reach this.
    private func attemptSeerrAutoLogin(credential: ServerCredential, jellyfinPassword: String) async {
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        guard let settings = try? await ArcfinSyncClient().fetchSettings(credential: credential, authHeader: header),
              let authMethod = settings.first(where: { $0.key == "seerrAuthMethod" }),
              authMethod.isLocked, authMethod.value == "jellyfin",
              let seerrURLSetting = settings.first(where: { $0.key == "seerrURL" }),
              let seerrURLString = seerrURLSetting.value, !seerrURLString.isEmpty
        else { return }

        UserDefaults.standard.set(seerrURLString, forKey: "seerrURL")
        UserDefaults.standard.set("jellyfin", forKey: "seerrAuthMethod")
        UserDefaults.standard.set(username, forKey: "seerrUsername")
        UserDefaults.standard.set(jellyfinPassword, forKey: "seerrPassword")
    }

    private func initiateQC() async {
        qcLoading = true
        qcCode = ""
        qcSecret = nil
        qcPolling = false
        authError = nil
        do {
            let (code, secret) = try await authManager.authClient.initiateQuickConnect(baseURL: serverURL)
            qcCode = formatCode(code)
            qcSecret = secret
            qcPolling = true
        } catch {
            authError = error.localizedDescription
        }
        qcLoading = false
    }

    private func pollQuickConnect(secret: String) async {
        for _ in 0..<40 {
            try? await Task.sleep(for: .seconds(3))
            guard qcPolling, !Task.isCancelled else { return }
            let approved = (try? await authManager.authClient.pollQuickConnect(baseURL: serverURL, secret: secret)) ?? false
            guard approved else { continue }
            do {
                let credential = try await authManager.authClient.authenticateWithQuickConnect(baseURL: serverURL, secret: secret)
                if let onAuthenticated {
                    onAuthenticated(credential)
                } else {
                    authManager.save(credential)
                    withAnimation { signedIn = true }
                }
            } catch {
                authError = error.localizedDescription
            }
            return
        }
        qcPolling = false
        authError = "Quick Connect timed out — please try again."
    }

    private func formatCode(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        guard digits.count >= 6 else { return raw }
        return "\(digits.prefix(3)) \(String(digits.dropFirst(3).prefix(3)))"
    }
}

// MARK: - AuthState helper

private extension AuthState {
    var displayName: String {
        if case .authenticated(let cred) = self { return cred.displayName }
        return ""
    }
}

#Preview {
    ZStack {
        DT.Color.backgroundPrimary.ignoresSafeArea()
        AuthView(serverURL: URL(string: "https://demo.jellyfin.org/stable")!, serverName: "Demo Server", onBack: {})
            .environment(AuthManager())
    }
}
