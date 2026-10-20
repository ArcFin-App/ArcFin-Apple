// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import SwiftUI
import AuthCore

/// Grouped by server (host) rather than UsersView's flat profile list — "Switch Server"
/// should ask which server first, and only ask which user within it if more than one is
/// signed in there. Presented as its own NavigationStack root, so it owns its own
/// navigationDestination(for:) rather than relying on an ancestor's (see the See All /
/// Downloads nav fix — a value pushed from a nested view can silently fail to resolve
/// against a destination declared further up an unrelated stack).
struct SwitchServerView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var pinStates: [UUID: Bool] = [:]
    @State private var switchTarget: ServerCredential?
    @State private var switchPINResetToken = 0
    @State private var switchPINError: String?
    @State private var switchStoredPIN: String?

    private var activeID: UUID? { authManager.state.credential?.id }

    private struct ServerGroup: Identifiable, Hashable {
        let host: String
        let profiles: [ServerCredential]
        var id: String { host }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.host == rhs.host }
        func hash(into hasher: inout Hasher) { hasher.combine(host) }
    }

    private var serverGroups: [ServerGroup] {
        Dictionary(grouping: authManager.profiles) { $0.baseURL.host ?? $0.baseURL.absoluteString }
            .map { ServerGroup(host: $0.key, profiles: $0.value) }
            .sorted { $0.host < $1.host }
    }

    var body: some View {
        List {
            ForEach(serverGroups) { group in
                if group.profiles.count == 1, let profile = group.profiles.first {
                    Button { handleTap(profile) } label: {
                        serverRow(group, subtitle: profile.displayName)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: group) {
                        serverRow(group, subtitle: "\(group.profiles.count) users")
                    }
                }
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .navigationTitle("Switch Server")
    #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
    #endif
        .navigationDestination(for: ServerGroup.self) { group in
            List {
                ForEach(group.profiles) { profile in
                    Button { handleTap(profile) } label: {
                        ProfileRowContent(profile: profile, isActive: profile.id == activeID, hasPIN: pinStates[profile.id] == true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .arcfinListStyle()
            .background(DT.Color.backgroundPrimary)
            .navigationTitle(group.host)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .task { await loadPINStates() }
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
                        dismiss()
                    } else {
                        switchPINError = "Incorrect PIN"
                        switchPINResetToken += 1
                    }
                }
            )
        }
    }

    private func serverRow(_ group: ServerGroup, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [DT.Color.accent, DT.Color.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                Image(systemName: "server.rack")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(group.host)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Text(subtitle)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            if group.profiles.contains(where: { $0.id == activeID }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DT.Color.accent)
            } else if group.profiles.count > 1 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func handleTap(_ profile: ServerCredential) {
        guard profile.id != activeID else { dismiss(); return }
        if pinStates[profile.id] == true {
            switchPINError = nil
            switchPINResetToken = 0
            Task {
                switchStoredPIN = await authManager.pin(for: profile.id)
                switchTarget = profile
            }
        } else {
            authManager.switchTo(profile)
            dismiss()
        }
    }

    private func loadPINStates() async {
        var states: [UUID: Bool] = [:]
        for profile in authManager.profiles {
            states[profile.id] = await authManager.pin(for: profile.id) != nil
        }
        pinStates = states
    }
}
#endif
