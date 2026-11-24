// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

extension View {
    /// On a shared account: who's watching, asked as the player opens (at most every 12 hours)
    /// or when the player's control for it is used, so each person's own progress follows along.
    func whoIsWatchingPrompt() -> some View {
        modifier(WhoIsWatchingPrompt())
    }
}

private struct WhoIsWatchingPrompt: ViewModifier {
    @Bindable private var companion = ServerCompanion.shared

    func body(content: Content) -> some View {
        content
            .onAppear { companion.playerOpened() }
            .appSheet(isPresented: $companion.askWhoIsWatching, title: "Who's Watching?", systemImage: "person.2") {
                if let shared = companion.sharedAccount {
                    NavigationStack {
                        WhoIsWatchingView(members: shared.members, watching: Set(shared.watching))
                    }
                }
            }
    }
}

/// Whether the player can offer "Who's Watching?" again.
enum SharedAccountWatching {
    @MainActor
    static var isAvailable: Bool {
        let companion = ServerCompanion.shared
        return companion.has("sharedAccounts") && companion.sharedAccount?.isShared == true
            && !(companion.sharedAccount?.members.isEmpty ?? true)
    }

    @MainActor
    static func ask() {
        ServerCompanion.shared.askWhoIsWatching = true
    }
}

struct WhoIsWatchingView: View {
    let members: [SharedAccountInfo.Person]

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String>

    init(members: [SharedAccountInfo.Person], watching: Set<String>) {
        self.members = members
        _picked = State(initialValue: watching)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            Text("Pick everyone watching. Each person's own watched list and progress follow along; with nobody picked, nothing is copied.")
                .font(DT.Font.callout)
                .foregroundStyle(DT.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: DT.Spacing.xs) {
                ForEach(members) { member in
                    let isOn = picked.contains(member.id)
                    Button {
                        if isOn { picked.remove(member.id) } else { picked.insert(member.id) }
                    } label: {
                        HStack {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isOn ? DT.Color.accent : DT.Color.textSecondary)
                            Text(member.name)
                                .foregroundStyle(DT.Color.textPrimary)
                            Spacer()
                        }
                        .font(DT.Font.body)
                        .padding(.horizontal, DT.Spacing.md)
                        .padding(.vertical, DT.Spacing.sm)
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Button {
                let chosen = members.map(\.id).filter(picked.contains)
                dismiss()
                Task { await ServerCompanion.shared.setWatching(chosen, authManager: authManager) }
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(DT.Color.accent)
            .controlSize(.large)
        }
        .padding(DT.Spacing.lg)
        .frame(maxWidth: 480)
        .sheetTitle("Who's Watching?")
    }
}
