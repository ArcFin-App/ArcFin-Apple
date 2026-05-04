import SwiftUI
import AuthCore
import JellyfinAPI

private enum AuthMode { case credentials, quickConnect }

struct AuthView: View {
    let serverURL: URL
    let serverName: String
    var onBack: () -> Void

    @Environment(AuthManager.self) private var authManager

    @State private var mode: AuthMode = .credentials

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

    // QC manual fallback
    @State private var digits: [String] = Array(repeating: "", count: 6)
    @State private var digitError: Bool = false
    @FocusState private var focusedDigit: Int?

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
                                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
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

                        Text("Choose how you'd like to authenticate")
                            .font(DT.Font.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                    .padding(.horizontal, DT.Spacing.pagePad)

                    modeToggle
                        .padding(.top, DT.Spacing.lg)
                        .padding(.horizontal, DT.Spacing.pagePad)

                    if mode == .credentials {
                        credentialsForm
                    } else {
                        quickConnectForm
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
            }
            .animation(DT.Animation.standard, value: mode)
            .onChange(of: mode) { _, newMode in
                authError = nil
                if newMode == .quickConnect {
                    Task { await initiateQC() }
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

    // MARK: - Mode toggle

    private var modeToggle: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 1))

            GeometryReader { geo in
                let halfW = (geo.size.width - 6) / 2
                RoundedRectangle(cornerRadius: 9)
                    .fill(DT.Color.accent.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(DT.Color.accent.opacity(0.35), lineWidth: 1))
                    .frame(width: halfW)
                    .offset(x: mode == .credentials ? 3 : halfW + 3)
                    .animation(DT.Animation.fast, value: mode)
            }

            HStack(spacing: 0) {
                modeButton("Password", .credentials)
                modeButton("Quick Connect", .quickConnect)
            }
        }
        .frame(height: 42)
    }

    private func modeButton(_ label: String, _ target: AuthMode) -> some View {
        Button { mode = target } label: {
            Text(label)
                .font(.system(size: 11, weight: mode == target ? .bold : .regular))
                .foregroundStyle(mode == target ? DT.Color.accent : DT.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Credentials form

    private var credentialsForm: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Username")
                glassField(icon: "person", placeholder: "jellyfin_user", text: $username, isSecure: false)
            }
            .padding(.top, DT.Spacing.md)
            .padding(.horizontal, DT.Spacing.pagePad)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Password")
                ZStack(alignment: .trailing) {
                    glassField(icon: "lock", placeholder: "••••••••", text: $password, isSecure: !passwordVisible)
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
                label: "Sign In", loadingLabel: "Signing in…",
                disabled: username.isEmpty || password.isEmpty
            ) { Task { await handleSignIn() } }
            .padding(.top, DT.Spacing.lg)
            .padding(.horizontal, DT.Spacing.pagePad)

            HStack(spacing: 4) {
                Text("Forgot password?").font(DT.Font.caption).foregroundStyle(DT.Color.textSecondary)
                Text("Reset via server").font(DT.Font.caption).foregroundStyle(DT.Color.accent).fontWeight(.medium)
            }
            .padding(.top, DT.Spacing.md)
        }
    }

    // MARK: - Quick Connect form

    private var quickConnectForm: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How Quick Connect works").font(.system(size: 11, weight: .bold)).foregroundStyle(DT.Color.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Open Jellyfin on your browser or another device")
                    Text("2. Go to **Dashboard → Quick Connect**")
                    Text("3. Enter the 6-digit code shown below")
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
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DT.Color.textSecondary)

                if qcLoading {
                    ProgressView().tint(DT.Color.accent).padding(.vertical, 10)
                } else if qcCode.isEmpty {
                    Text("—").font(.system(size: 22, weight: .heavy, design: .monospaced)).foregroundStyle(DT.Color.textSecondary)
                } else {
                    codeDisplay(qcCode)
                    if qcPolling {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7).tint(DT.Color.accent)
                            Text("Waiting for approval…").font(DT.Font.caption2).foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                }
            }
            .padding(.top, DT.Spacing.lg)

            if !qcCode.isEmpty {
                Divider()
                    .background(.white.opacity(0.07))
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.vertical, DT.Spacing.md)

                VStack(spacing: 10) {
                    Text("Or enter code manually")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DT.Color.textSecondary)

                    digitInputRow

                    if digitError {
                        Text("Invalid code — please try again")
                            .font(DT.Font.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)

                signInButton(
                    label: "Verify Code", loadingLabel: "Verifying…", disabled: false
                ) { Task { await handleManualQC() } }
                .padding(.top, DT.Spacing.md)
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
    }

    private func codeDisplay(_ code: String) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(code.enumerated()), id: \.offset) { i, ch in
                if ch == " " {
                    Spacer().frame(width: 8)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DT.Color.accent.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.accent.opacity(0.3), lineWidth: 1.5))
                            .frame(width: 36, height: 46)
                            .shadow(color: DT.Color.accent.opacity(0.08), radius: 8)
                        Text(String(ch))
                            .font(.system(size: 22, weight: .heavy, design: .monospaced))
                            .foregroundStyle(DT.Color.accent)
                    }
                }
            }
        }
    }

    private var digitInputRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<6) { i in
                if i == 3 {
                    Circle().fill(.white.opacity(0.3)).frame(width: 4, height: 4)
                }
                digitBox(index: i)
            }
        }
    }

    private func digitBox(index: Int) -> some View {
        let strokeColor: Color = {
            if digitError { return Color.red.opacity(0.5) }
            if digits[index].isEmpty { return Color.white.opacity(0.1) }
            return DT.Color.accent.opacity(0.5)
        }()
        let bgColor: Color = digitError ? Color.red.opacity(0.08) : Color.white.opacity(0.06)
        return TextField("", text: $digits[index])
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .heavy, design: .monospaced))
            .foregroundStyle(DT.Color.textPrimary)
            .multilineTextAlignment(.center)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .focused($focusedDigit, equals: index)
            .frame(width: 38, height: 48)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(strokeColor, lineWidth: 1.5))
            .onChange(of: digits[index]) { _, newVal in
                let filtered = String(newVal.filter { $0.isNumber }.prefix(1))
                if filtered != newVal { digits[index] = filtered }
                digitError = false
                if !filtered.isEmpty, index < 5 { focusedDigit = index + 1 }
                if !filtered.isEmpty, index == 5 { Task { await handleManualQC() } }
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
                    : AnyShapeStyle(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            .shadow(color: disabled ? .clear : DT.Color.accent.opacity(0.3), radius: 16)
        }
        .buttonStyle(.plain)
        .disabled(signingIn || disabled)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(DT.Color.textSecondary)
    }

    private func glassField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(DT.Color.textSecondary)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(DT.Font.caption).foregroundStyle(DT.Color.textPrimary).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(DT.Font.caption).foregroundStyle(DT.Color.textPrimary).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .arcfinFieldBackground()
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.md).stroke(.white.opacity(0.1), lineWidth: 1))
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

    private func handleSignIn() async {
        authError = nil
        signingIn = true
        do {
            let credential = try await authManager.authClient.authenticate(
                baseURL: serverURL, username: username, password: password
            )
            authManager.save(credential)
            withAnimation { signedIn = true }
        } catch {
            authError = error.localizedDescription
        }
        signingIn = false
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
                authManager.save(credential)
                withAnimation { signedIn = true }
            } catch {
                authError = error.localizedDescription
            }
            return
        }
        qcPolling = false
        authError = "Quick Connect timed out — please try again."
    }

    private func handleManualQC() async {
        let code = digits.joined()
        guard code.count == 6 else { return }
        guard let secret = qcSecret else {
            authError = "No active Quick Connect session."
            return
        }
        signingIn = true
        authError = nil
        do {
            let approved = try await authManager.authClient.pollQuickConnect(baseURL: serverURL, secret: secret)
            if approved {
                let credential = try await authManager.authClient.authenticateWithQuickConnect(baseURL: serverURL, secret: secret)
                authManager.save(credential)
                withAnimation { signedIn = true }
            } else {
                digitError = true
                digits = Array(repeating: "", count: 6)
                focusedDigit = 0
            }
        } catch {
            authError = error.localizedDescription
        }
        signingIn = false
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
