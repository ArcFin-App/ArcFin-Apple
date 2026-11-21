// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import CoreImage.CIFilterBuiltins
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
    /// The server has Quick Connect turned off, so the page moved to the password.
    @State private var qcDisabled: Bool = false

    var body: some View {
        if signedIn {
            successView
        } else {
            Group {
                if !PlatformMetrics.loginSideBySide {
                    formPage
                } else if mode == .quickConnect {
                    quickConnectPage
                } else {
                    passwordPage
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

    // MARK: - Layouts

    /// One column: the method picker, then Quick Connect or the password fields.
    private var formPage: some View {
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

            quickConnectOffNotice

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
    }

    /// Apple TV: the steps on the left with a way to use a password instead, and the QR code
    /// with the code under it on the right.
    private var quickConnectPage: some View {
        LoginSplitPage {
            LoginBackButton(title: serverName, action: onBack)
            LoginSplitHeader(title: "Sign In", message: Text("Approve this device from Jellyfin on a phone, computer or TV where you're already signed in."))
            expiredNotice
            NearbySetupHint()
            VStack(alignment: .leading, spacing: 18) {
                step(1, "Open Jellyfin where you're already signed in.")
                step(2, "Go to your profile, then Quick Connect.")
                step(3, "Enter the code on the right.")
            }
            errorLabel
            HStack(spacing: 24) {
                Button { mode = .credentials } label: {
                    Label("Sign In with Password", systemImage: "key").loginLinkPadding()
                }
                if !qcPolling && !qcLoading {
                    Button { Task { await initiateQC() } } label: {
                        Text("Get a New Code").loginLinkPadding()
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(DT.Color.accent)
            .arcfinPlainButton(cornerRadius: DT.Radius.pill)
        } trailing: {
            // No panel without a code coming: a failed request left it spinning for good.
            if qcLoading || qcPolling {
                Group {
                    if qcPolling, let link = QuickConnectLink.url(server: serverURL, code: qcCode.filter(\.isNumber)),
                       let image = QuickConnectQR.image(for: link) {
                        Image(decorative: image, scale: 1)
                            .interpolation(.none)
                            .resizable()
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 400, height: 400)
                .padding(24)
                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .accessibilityLabel("QR code to sign in")
                Text("Scan with your iPhone's Camera")
                    .font(.footnote)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if !qcCode.isEmpty {
                Text(qcCode)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .tracking(8)
                    .foregroundStyle(DT.Color.textPrimary)
                    .accessibilityLabel("Code \(qcCode.map(String.init).joined(separator: " "))")
            }
            if qcPolling {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval")
                        .font(.footnote)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
    }

    /// Apple TV: what's being signed in to on the left, with Quick Connect to go back to, and
    /// the fields on the right.
    private var passwordPage: some View {
        LoginSplitPage {
            LoginBackButton(title: serverName, action: onBack)
            LoginSplitHeader(title: "Sign In", message: Text("Use your Jellyfin username and password for \(serverName)."))
            expiredNotice
            quickConnectOffNotice
            Button { mode = .quickConnect } label: {
                Label("Sign In with Quick Connect", systemImage: "qrcode").loginLinkPadding()
            }
            .font(.callout)
            .foregroundStyle(DT.Color.accent)
            .arcfinPlainButton(cornerRadius: DT.Radius.pill)
        } trailing: {
            credentialsView
            errorLabel
            LoginPrimaryButton(title: "Sign In", busyTitle: "Signing In…", isBusy: signingIn,
                               isDisabled: username.isEmpty) {
                Task { await handleSignIn() }
            }
        }
    }

    @ViewBuilder
    private var expiredNotice: some View {
        if authManager.expiredCredential?.baseURL == serverURL {
            Label("Your sign-in to this server has ended, usually because the password changed or this device was removed from the server. Sign in again to carry on.", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(DT.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var quickConnectOffNotice: some View {
        if qcDisabled && mode == .credentials {
            Label("Quick Connect is turned off on this server, so sign in with your username and password.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(DT.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let err = authError {
            Label(err, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
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
        } catch JellyfinAuthError.quickConnectDisabled {
            qcDisabled = true
            mode = .credentials
        } catch {
            authError = error.localizedDescription
        }
        qcLoading = false
    }

    /// Jellyfin's codes last ten minutes; then there's a new one, rather than an error, since
    /// the Apple TV may have been left on this screen.
    private func pollQuickConnect(secret: String) async {
        for _ in 0..<195 {
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
        // Outside this task, which ends as soon as the new code replaces the secret it polls.
        Task { await initiateQC() }
    }

    private func formatCode(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        guard digits.count >= 6 else { return raw }
        return "\(digits.prefix(3)) \(String(digits.dropFirst(3).prefix(3)))"
    }
}

/// The Quick Connect link as a QR code, drawn sharp at any size.
private enum QuickConnectQR {
    static func image(for link: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return CIContext().createCGImage(scaled, from: scaled.extent)
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
