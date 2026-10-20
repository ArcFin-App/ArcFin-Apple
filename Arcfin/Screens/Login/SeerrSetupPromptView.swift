// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// Shown once after a sign-in that left Seerr unconfigured because no password was available
/// to auto-fill it (Quick Connect) — password-based sign-in already fills this in silently via
/// AuthView's attemptSeerrAutoLogin. Seerr Account Type is locked to Jellyfin server-side here,
/// which is exactly why Settings hides the manual username/password fields that would
/// otherwise let the user fix this themselves — this is the one place that gap can still be
/// closed, since the password only ever exists transiently at sign-in.
struct SeerrSetupPromptView: View {
    let seerrURL: String
    let jellyfinUsername: String
    let onConnected: (_ username: String, _ password: String) -> Void
    let onDismiss: () -> Void

    private enum Step {
        case ask, password, testing, failed
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
                    .font(.system(size: 44))
                    .foregroundStyle(DT.Color.accent)

                switch step {
                case .ask:
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
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
            #endif
        }
        .interactiveDismissDisabled()
    }

    private var askContent: some View {
        VStack(spacing: 16) {
            Text("Connect Seerr")
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("This server uses Seerr to handle media requests and more. Would you like to connect it now?")
                .font(.system(.subheadline))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button {
                    step = .password
                } label: {
                    Text("Yes, Connect Now")
                        .font(.system(.callout, design: .default, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(DT.Color.accent)

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Not Right Now")
                        .font(.system(.subheadline))
                }
                .foregroundStyle(DT.Color.textSecondary)
            }
            .frame(maxWidth: 320)
            .padding(.top, 8)

            Text("You can also ask your admin to connect this for you — initial sign-in is the only time it can be set up here, since this setting is locked.")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.7))
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
                #if !os(tvOS)
                // .roundedBorder is unavailable on tvOS — its SecureField already renders
                // with the system's own default appearance there, no style needed.
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit(testPassword)
                #endif
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
                        ProgressView().tint(.white)
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
                errorMessage = "That password was incorrect — try again."
                step = .failed
            } catch {
                errorMessage = "Couldn't reach Seerr right now — try again."
                step = .failed
            }
        }
    }
}

#Preview {
    SeerrSetupPromptView(
        seerrURL: "https://seerr.example.com",
        jellyfinUsername: "alex",
        onConnected: { _, _ in },
        onDismiss: {}
    )
}
