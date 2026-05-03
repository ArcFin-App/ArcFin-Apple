import SwiftUI

private enum AuthMode { case credentials, quickConnect }

private let quickConnectCode = "482 917"

struct AuthView: View {
    let serverURL: String
    var onBack: () -> Void
    var onAuthenticated: () -> Void

    @State private var mode: AuthMode = .credentials
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var passwordVisible: Bool = false
    @State private var signingIn: Bool = false
    @State private var signedIn: Bool = false

    // Quick Connect manual entry
    @State private var digits: [String] = Array(repeating: "", count: 6)
    @State private var digitError: Bool = false
    @FocusState private var focusedDigit: Int?

    private var serverHost: String {
        serverURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "/").first ?? serverURL
    }

    var body: some View {
        if signedIn {
            successView
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    stepIndicator

                    ArcfinLogoView(size: 52)
                        .padding(.top, 24)

                    // Back + title
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(serverHost)
                                    .font(DT.Font.caption)
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

                    // Segmented mode toggle
                    modeToggle
                        .padding(.top, DT.Spacing.lg)
                        .padding(.horizontal, DT.Spacing.pagePad)

                    // Content
                    if mode == .credentials {
                        credentialsForm
                    } else {
                        quickConnectForm
                    }
                }
                .padding(.top, 52)
                .padding(.bottom, DT.Spacing.xxxl)
            }
            .animation(DT.Animation.standard, value: mode)
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(DT.Color.accent.opacity(0.4))
                .frame(width: 6, height: 6)
            Capsule()
                .fill(DT.Color.accent)
                .frame(width: 20, height: 6)
        }
    }

    // MARK: - Mode toggle (glass segmented control)

    private var modeToggle: some View {
        ZStack(alignment: .leading) {
            // Track
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

            // Sliding indicator
            GeometryReader { geo in
                let halfW = (geo.size.width - 6) / 2
                RoundedRectangle(cornerRadius: 9)
                    .fill(DT.Color.accent.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(DT.Color.accent.opacity(0.35), lineWidth: 1)
                    )
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

    private func modeButton(_ label: String, _ targetMode: AuthMode) -> some View {
        Button { mode = targetMode } label: {
            Text(label)
                .font(.system(size: 11, weight: mode == targetMode ? .bold : .regular))
                .foregroundStyle(mode == targetMode ? DT.Color.accent : DT.Color.textSecondary)
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
                glassField(
                    icon: "person",
                    placeholder: "jellyfin_user",
                    text: $username,
                    isSecure: false
                )
            }
            .padding(.top, DT.Spacing.md)
            .padding(.horizontal, DT.Spacing.pagePad)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Password")
                ZStack(alignment: .trailing) {
                    glassField(
                        icon: "lock",
                        placeholder: "••••••••",
                        text: $password,
                        isSecure: !passwordVisible
                    )
                    Button {
                        passwordVisible.toggle()
                    } label: {
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
                disabled: username.isEmpty || password.isEmpty,
                action: handleSignIn
            )
            .padding(.top, DT.Spacing.lg)
            .padding(.horizontal, DT.Spacing.pagePad)

            HStack(spacing: 4) {
                Text("Forgot password?")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                Text("Reset via server")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.accent)
                    .fontWeight(.medium)
            }
            .padding(.top, DT.Spacing.md)
        }
    }

    // MARK: - Quick Connect form

    private var quickConnectForm: some View {
        VStack(spacing: 0) {
            // Instruction panel
            VStack(alignment: .leading, spacing: 6) {
                Text("How Quick Connect works")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DT.Color.accent)

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
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.md)
                    .stroke(DT.Color.accent.opacity(0.15), lineWidth: 1)
            )
            .padding(.top, DT.Spacing.md)
            .padding(.horizontal, DT.Spacing.pagePad)

            // Code display
            VStack(spacing: 12) {
                Text("Your Quick Connect Code")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DT.Color.textSecondary)

                codeDisplay(quickConnectCode)

                Text("Expires in ")
                    .font(DT.Font.caption2)
                    .foregroundStyle(DT.Color.textSecondary)
                +
                Text("4:58")
                    .font(DT.Font.caption2)
                    .foregroundStyle(DT.Color.textPrimary)
            }
            .padding(.top, DT.Spacing.lg)

            Divider()
                .background(.white.opacity(0.07))
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.vertical, DT.Spacing.md)

            // Manual entry
            VStack(spacing: 10) {
                Text("Or enter the code from another device")
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
                label: "Verify Code",
                loadingLabel: "Verifying…",
                disabled: false,
                action: handleQuickConnect
            )
            .padding(.top, DT.Spacing.md)
            .padding(.horizontal, DT.Spacing.pagePad)
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
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(DT.Color.accent.opacity(0.3), lineWidth: 1.5)
                            )
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
                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 4, height: 4)
                }

                digitBox(index: i)
            }
        }
    }

    private func digitBox(index: Int) -> some View {
        TextField("", text: $digits[index])
            .font(.system(size: 20, weight: .heavy, design: .monospaced))
            .foregroundStyle(DT.Color.textPrimary)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .focused($focusedDigit, equals: index)
            .frame(width: 38, height: 48)
            .background(digitError ? Color.red.opacity(0.08) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        digitError ? Color.red.opacity(0.5) :
                            digits[index].isEmpty ? Color.white.opacity(0.1) :
                            DT.Color.accent.opacity(0.5),
                        lineWidth: 1.5
                    )
            )
            .onChange(of: digits[index]) { _, newVal in
                let filtered = String(newVal.filter(\.isNumber).prefix(1))
                if filtered != newVal {
                    digits[index] = filtered
                }
                digitError = false
                if !filtered.isEmpty, index < 5 {
                    focusedDigit = index + 1
                }
                if !filtered.isEmpty, index == 5 {
                    handleQuickConnect()
                }
            }
    }

    // MARK: - Shared button

    private func signInButton(label: String, loadingLabel: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if signingIn {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white).scaleEffect(0.85)
                        Text(loadingLabel)
                            .font(DT.Font.button)
                            .foregroundStyle(.white.opacity(0.8))
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
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
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
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(DT.Color.textSecondary)

            if isSecure {
                SecureField(placeholder, text: text)
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: text)
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.06))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Success

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
                    Text("Welcome back")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("Opening your library…")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onAuthenticated()
            }
        }
    }

    // MARK: - Actions

    private func handleSignIn() {
        guard !username.isEmpty, !password.isEmpty else { return }
        signingIn = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { signedIn = true }
        }
    }

    private func handleQuickConnect() {
        let code = digits.joined()
        guard code.count == 6 else { return }
        let expected = quickConnectCode.replacingOccurrences(of: " ", with: "")
        if code == expected {
            signingIn = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { signedIn = true }
            }
        } else {
            digitError = true
            digits = Array(repeating: "", count: 6)
            focusedDigit = 0
        }
    }
}

#Preview {
    ZStack {
        DT.Color.backgroundPrimary.ignoresSafeArea()
        AuthView(serverURL: "https://media.home.local:8096", onBack: {}, onAuthenticated: {})
    }
}
