#if !os(tvOS)
import SwiftUI
import AuthCore
import JellyfinAPI

// MARK: - Users screen

struct UsersView: View {
    var onExpand: (() -> Void)? = nil

    @Environment(AuthManager.self) private var authManager

    @State private var pinStates: [UUID: Bool] = [:]
    @State private var switchTarget: ServerCredential? = nil
    @State private var switchPINResetToken = 0
    @State private var switchPINError: String? = nil
    @State private var switchStoredPIN: String? = nil
    @State private var showAddProfile = false

    private var activeID: UUID? { authManager.state.credential?.id }

    private var activeProfile: ServerCredential? {
        authManager.profiles.first { $0.id == activeID }
    }

    private var otherProfiles: [ServerCredential] {
        authManager.profiles.filter { $0.id != activeID }
    }

    var body: some View {
        List {
            // ── Current profile ──────────────────────────────────────────
            if let active = activeProfile {
                Section {
                    NavigationLink {
                        ProfileDetailView(profile: active)
                    } label: {
                        ProfileRowContent(
                            profile: active,
                            isActive: true,
                            hasPIN: pinStates[active.id] == true
                        )
                    }
                } header: { sectionLabel("Current Profile") }
            }

            // ── Other profiles ───────────────────────────────────────────
            if !otherProfiles.isEmpty {
                Section {
                    ForEach(otherProfiles) { profile in
                        Button {
                            handleTapOtherProfile(profile)
                        } label: {
                            ProfileRowContent(
                                profile: profile,
                                isActive: false,
                                hasPIN: pinStates[profile.id] == true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indices in
                        for i in indices {
                            authManager.removeProfile(id: otherProfiles[i].id)
                        }
                        Task { await loadPINStates() }
                    }
                } header: { sectionLabel("Switch To") }
            }

            // ── Add profile ───────────────────────────────────────────────
            Section {
                Button {
                    onExpand?()
                    showAddProfile = true
                } label: {
                    Label("Add Profile", systemImage: "plus.circle.fill")
                        .foregroundStyle(DT.Color.accent)
                }
                .buttonStyle(.plain)
                .navigationDestination(isPresented: $showAddProfile) {
                    AddProfileFlowView()
                }
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPINStates() }
        .onChange(of: authManager.profiles) { _, _ in Task { await loadPINStates() } }
        // PIN entry sheet for switching to a protected profile
        .sheet(item: $switchTarget) { target in
            PINEntrySheet(
                title: "Switch to \(target.displayName)",
                subtitle: target.baseURL.host,
                storedPIN: switchStoredPIN,
                resetToken: switchPINResetToken,
                errorMessage: switchPINError,
                onCancel: {
                    switchTarget = nil
                    switchPINError = nil
                },
                onComplete: { entered in
                    if entered == switchStoredPIN {
                        authManager.switchTo(target)
                        switchTarget = nil
                        switchPINError = nil
                        Task { await loadPINStates() }
                    } else {
                        switchPINError = "Incorrect PIN"
                        switchPINResetToken += 1
                    }
                }
            )
        }
    }

    // MARK: - Actions

    private func handleTapOtherProfile(_ profile: ServerCredential) {
        if pinStates[profile.id] == true {
            switchPINError = nil
            switchPINResetToken = 0
            Task {
                switchStoredPIN = await authManager.pin(for: profile.id)
                switchTarget = profile
            }
        } else {
            authManager.switchTo(profile)
            Task { await loadPINStates() }
        }
    }

    private func loadPINStates() async {
        var states: [UUID: Bool] = [:]
        for profile in authManager.profiles {
            states[profile.id] = await authManager.pin(for: profile.id) != nil
        }
        pinStates = states
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
    }
}

// MARK: - Profile row content

struct ProfileRowContent: View {
    let profile: ServerCredential
    let isActive: Bool
    let hasPIN: Bool

    private var initials: String {
        profile.displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [DT.Color.accent, DT.Color.accentDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                    .shadow(color: isActive ? DT.Color.accent.opacity(0.35) : .clear, radius: 8)
                Text(initials)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)

                Text(profile.baseURL.host ?? profile.baseURL.absoluteString)
                    .font(.system(size: 12))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: hasPIN ? "lock.fill" : "lock.open")
                        .font(.system(size: 10))
                        .foregroundStyle(hasPIN ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
                    Text(hasPIN ? "PIN enabled" : "No PIN")
                        .font(.system(size: 11))
                        .foregroundStyle(hasPIN ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
                }
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DT.Color.accent)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Profile detail (PIN management)

struct ProfileDetailView: View {
    let profile: ServerCredential
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var hasPIN = false
    @State private var pinFlow: PINFlow? = nil

    enum PINFlow: Identifiable {
        case setNew, changeVerifyCurrent, disableVerifyCurrent
        var id: Int { hashValue }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Name") {
                    Text(profile.displayName).foregroundStyle(.secondary)
                }
                LabeledContent("Server") {
                    Text(profile.baseURL.host ?? profile.baseURL.absoluteString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } header: { sectionLabel("Profile") }

            Section {
                if hasPIN {
                    Button("Change PIN") { pinFlow = .changeVerifyCurrent }
                        .foregroundStyle(DT.Color.accent)
                    Button("Disable PIN Protection", role: .destructive) {
                        pinFlow = .disableVerifyCurrent
                    }
                } else {
                    Button("Enable PIN Protection") { pinFlow = .setNew }
                        .foregroundStyle(DT.Color.accent)
                }
            } header: {
                sectionLabel("Security")
            } footer: {
                Text(hasPIN
                     ? "A 4-digit PIN is required when switching to this profile."
                     : "Add a PIN to require verification before switching to this profile.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            if authManager.state.credential?.id != profile.id {
                Section {
                    Button("Remove Profile", role: .destructive) {
                        authManager.removeProfile(id: profile.id)
                        dismiss()
                    }
                }
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { hasPIN = await authManager.pin(for: profile.id) != nil }
        .sheet(item: $pinFlow) { flow in
            PINFlowSheet(profile: profile, flow: flow) {
                hasPIN = await authManager.pin(for: profile.id) != nil
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
    }
}

// MARK: - PIN flow sheet (set / change / disable)

private struct PINFlowSheet: View {
    let profile: ServerCredential
    let flow: ProfileDetailView.PINFlow
    var onDone: () async -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // Stage machine
    @State private var stage: Stage = .first
    @State private var pendingPIN: String? = nil
    @State private var resetToken = 0
    @State private var errorMessage: String? = nil
    @State private var storedPIN: String? = nil

    enum Stage { case first, second }

    private var firstTitle: String {
        switch flow {
        case .setNew:                   return "Enter new PIN"
        case .changeVerifyCurrent:      return "Enter current PIN"
        case .disableVerifyCurrent:     return "Enter PIN to disable"
        }
    }

    private var secondTitle: String {
        switch flow {
        case .setNew:              return "Confirm PIN"
        case .changeVerifyCurrent: return "Enter new PIN"
        default:                   return ""
        }
    }

    var body: some View {
        switch stage {
        case .first:
            PINPadView(
                title: firstTitle,
                subtitle: profile.displayName,
                errorMessage: errorMessage,
                resetToken: resetToken,
                onCancel: { dismiss() },
                onComplete: handleFirst
            )
            .task { storedPIN = await authManager.pin(for: profile.id) }

        case .second:
            PINPadView(
                title: secondTitle,
                subtitle: profile.displayName,
                errorMessage: errorMessage,
                resetToken: resetToken,
                onCancel: { stage = .first; errorMessage = nil },
                onComplete: handleSecond
            )
        }
    }

    private func handleFirst(_ entered: String) {
        switch flow {
        case .setNew:
            pendingPIN = entered
            errorMessage = nil
            stage = .second

        case .changeVerifyCurrent:
            if entered == storedPIN {
                pendingPIN = nil
                errorMessage = nil
                stage = .second
            } else {
                errorMessage = "Incorrect PIN"
                resetToken += 1
            }

        case .disableVerifyCurrent:
            if entered == storedPIN {
                authManager.removePin(for: profile.id)
                Task { await onDone(); dismiss() }
            } else {
                errorMessage = "Incorrect PIN"
                resetToken += 1
            }
        }
    }

    private func handleSecond(_ entered: String) {
        switch flow {
        case .setNew:
            if entered == pendingPIN {
                authManager.savePin(entered, for: profile.id)
                Task { await onDone(); dismiss() }
            } else {
                errorMessage = "PINs don't match"
                resetToken += 1
            }

        case .changeVerifyCurrent:
            // Second stage = confirm new PIN (no repeat needed for simplicity — save directly)
            authManager.savePin(entered, for: profile.id)
            Task { await onDone(); dismiss() }

        default: break
        }
    }
}

// MARK: - PIN entry sheet (for switching profiles)

struct PINEntrySheet: View {
    let title: String
    var subtitle: String? = nil
    let storedPIN: String?
    var resetToken: Int
    var errorMessage: String?
    var onCancel: () -> Void
    var onComplete: (String) -> Void

    var body: some View {
        PINPadView(
            title: title,
            subtitle: subtitle,
            errorMessage: errorMessage,
            resetToken: resetToken,
            onCancel: onCancel,
            onComplete: onComplete
        )
    }
}

// MARK: - Add profile flow (pushed inside UsersView's NavigationStack)

struct AddProfileFlowView: View {
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
                    dismiss()
                }
            )
            .navigationBarBackButtonHidden(true)
        }
    }
}
#endif
