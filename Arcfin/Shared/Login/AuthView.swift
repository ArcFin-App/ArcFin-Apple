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
            VStack(alignment: .leading, spacing: 28) {
                LoginBackButton(title: serverName, action: onBack)

                LoginHeader(
                    title: "Sign In",
                    message: mode == .quickConnect
                        ? "Approve this device from Jellyfin on a phone, computer or TV where you're already signed in."
                        : "Use your Jellyfin username and password for \(serverName)."
                )

                if authManager.expiredCredential?.baseURL == serverURL {
                    Label("Your sign-in to this server has ended, usually because the password changed or this device was removed from the server. Sign in again to carry on.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(DT.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Sign-in method", selection: $mode) {
                    Text("Quick Connect").tag(AuthMode.quickConnect)
                    Text("Password").tag(AuthMode.credentials)
                }
                .pickerStyle(.segmented)

                if mode == .quickConnect {
                    quickConnectView
                } else {
                    credentialsView
                }

                if let err = authError {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .loginLayout {
                if mode == .credentials {
                    LoginPrimaryButton(title: "Sign In", busyTitle: "Signing In…", isBusy: signingIn,
                                       // Password is deliberately optional: Jellyfin allows accounts
                                       // with no password (common for kids' and demo profiles).
                                       isDisabled: username.isEmpty) {
                        Task { await handleSignIn() }
                    }
                }
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

    // MARK: - Quick Connect (default)

    private var quickConnectView: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("Your Code")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DT.Color.textSecondary)
                if qcLoading || qcCode.isEmpty {
                    ProgressView().frame(height: 56)
                } else {
                    Text(qcCode)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .tracking(6)
                        .foregroundStyle(DT.Color.textPrimary)
                        .quickConnectCodeSelection()
                        .accessibilityLabel("Code \(qcCode.map(String.init).joined(separator: " "))")
                }
                if qcPolling {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for approval")
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                step(1, "Open Jellyfin where you're already signed in.")
                step(2, "Go to your profile, then Quick Connect.")
                step(3, "Enter the code above.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !qcPolling && !qcLoading {
                Button("Get a New Code") { Task { await initiateQC() } }
                    .font(.subheadline)
                    .foregroundStyle(DT.Color.accent)
                    .arcfinPlainButton(cornerRadius: DT.Radius.pill)
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(DT.Color.accent)
                .frame(width: 24, height: 24)
                .background(DT.Color.accent.opacity(0.15), in: Circle())
            Text(text)
                .font(.callout)
                .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Credentials

    private var credentialsView: some View {
        VStack(spacing: 18) {
            LoginTextField(title: "Username", prompt: Text("Username"), text: $username, kind: .username)
            LoginTextField(title: "Password", prompt: Text("Password"), text: $password, kind: .password,
                           onSubmit: submitCredentials)
        }
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
                        .font(.system(.title2, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                }
                VStack(spacing: 6) {
                    Text("Welcome, \(authManager.state.displayName)!")
                        .font(.system(.body, design: .default, weight: .bold))
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
    /// use (this one-shot check + prefill), persisted through AuthManager.saveSeerrPassword
    /// (Keychain) the same way SeerrPluginView persists a password a user types in by hand.
    /// Quick Connect sign-in never has a password at all, so it can't reach this.
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
        authManager.saveSeerrPassword(jellyfinPassword)
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
        authError = String(localized: "Quick Connect timed out — please try again.")
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
