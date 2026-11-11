// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// Shown when the server gives a Seerr address but connecting it by itself through Quick
/// Connect didn't work (see AppRootModel.checkSeerrSetupPrompt): it opens at the password,
/// saying why. Connect tries Quick Connect again.
struct SeerrSetupPromptView: View {
    let seerrURL: String
    let jellyfinUsername: String
    let authorizeQuickConnect: SeerrHTTPClient.QuickConnectAuthorizer
    /// Quick Connect was already tried and failed for this reason: start at the password.
    var initialError: String?
    /// An empty password means Seerr was connected through Quick Connect.
    let onConnected: (_ username: String, _ password: String) -> Void
    let onDismiss: () -> Void

    private enum Step {
        case ask, connecting, password, testing, failed
    }

    @State private var step: Step = .ask
    @State private var password = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "sparkles.tv")
                    .scaledFont(size: 44)
                    .foregroundStyle(DT.Color.accent)

                switch step {
                case .ask, .connecting:
                    askContent
                case .password, .testing:
                    passwordContent
                case .failed:
                    passwordContent
                }

                Spacer()
            }
            .padding(32)
            .background(DT.Color.backgroundPrimary)
            .seerrPromptNotNowButton {
                onDismiss()
                dismiss()
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard let initialError else { return }
            errorMessage = initialError
            step = .password
        }
    }

    private var askContent: some View {
        VStack(spacing: 16) {
            Text("Connect Seerr")
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("This server uses Seerr to handle media requests and more. Connect it with your Jellyfin account (\(jellyfinUsername)); there's no password to type.")
                .font(.system(.subheadline))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button(action: connectWithQuickConnect) {
                    Group {
                        if step == .connecting {
                            ProgressView().tint(DT.Color.onAccent)
                        } else {
                            Text("Connect")
                                .font(.system(.callout, design: .default, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)
                .disabled(step == .connecting)
                .accessibilityLabel(step == .connecting ? "Connecting" : "Connect")

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Not Right Now")
                        .font(.system(.subheadline))
                }
                .foregroundStyle(DT.Color.textSecondary)
                .disabled(step == .connecting)
            }
            .frame(maxWidth: 320)
            .padding(.top, 8)

            Text("You can also ask your admin to connect this for you — initial sign-in is the only time it can be set up here, since this setting is locked.")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
    }

    private var passwordContent: some View {
        VStack(spacing: 16) {
            Text("Enter Your Password")
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Seerr uses the same Jellyfin account (\(jellyfinUsername)) — this is only used to connect Seerr and isn't stored anywhere else.")
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)

            SecureField("Password", text: $password)
                .seerrPasswordFieldStyle(onSubmit: testPassword)
                .frame(maxWidth: 280)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button(action: testPassword) {
                    if step == .testing {
                        ProgressView().tint(DT.Color.onAccent)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .font(.system(.callout, design: .default, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .buttonStyle(.borderedProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)
                .disabled(password.isEmpty || step == .testing)

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Not Right Now")
                        .font(.system(.subheadline))
                }
                .foregroundStyle(DT.Color.textSecondary)
                .disabled(step == .testing)
            }
            .frame(maxWidth: 320)
            .padding(.top, 8)
        }
    }

    private func connectWithQuickConnect() {
        errorMessage = nil
        step = .connecting
        Task {
            let client = SeerrHTTPClient(
                baseURL: URL(string: seerrURL) ?? URL(fileURLWithPath: "/"),
                username: jellyfinUsername, password: "", authMethod: .jellyfin,
                authorizeQuickConnect: authorizeQuickConnect
            )
            do {
                try await client.login()
                onConnected(jellyfinUsername, "")
                dismiss()
            } catch {
                // Quick Connect can't be used here: the password still can.
                errorMessage = SeerrSignInText.message(for: error)
                step = .password
            }
        }
    }

    private func testPassword() {
        guard !password.isEmpty else { return }
        errorMessage = nil
        step = .testing
        Task {
            let client = SeerrHTTPClient(
                baseURL: URL(string: seerrURL) ?? URL(fileURLWithPath: "/"),
                username: jellyfinUsername, password: password, authMethod: .jellyfin
            )
            do {
                try await client.login()
                onConnected(jellyfinUsername, password)
                dismiss()
            } catch SeerrError.authFailed {
                errorMessage = String(localized: "That password was incorrect — try again.")
                step = .failed
            } catch {
                errorMessage = String(localized: "Couldn't reach Seerr right now — try again.")
                step = .failed
            }
        }
    }
}

#Preview {
    SeerrSetupPromptView(
        seerrURL: "https://seerr.example.com",
        jellyfinUsername: "alex",
        authorizeQuickConnect: { _ in true },
        initialError: nil,
        onConnected: { _, _ in },
        onDismiss: {}
    )
}
