// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

extension View {
    /// On a shared account, who's watching: asked once a session over the app, once the lock is
    /// out of the way, so each person's progress follows along for everything played.
    func whoIsWatchingPrompt(locked: Bool) -> some View {
        modifier(WhoIsWatchingPrompt(inPlayer: nil, locked: locked))
    }

    /// The same question over the player, asked from its control or when a session starts with
    /// it open. Playback pauses while it's asked.
    func whoIsWatchingPrompt(pausing player: PlayerModel) -> some View {
        modifier(WhoIsWatchingPrompt(inPlayer: player, locked: false))
    }
}

private struct WhoIsWatchingPrompt: ViewModifier {
    let inPlayer: PlayerModel?
    let locked: Bool
    @Bindable private var companion = ServerCompanion.shared

    /// The player asks while it's open, the app the rest of the time, so only one shows it.
    private var isShown: Binding<Bool> {
        Binding {
            companion.askWhoIsWatching && !locked && (inPlayer != nil) == PlayerActivity.shared.isPlayerOpen
        } set: {
            companion.askWhoIsWatching = $0
        }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: isShown.wrappedValue) { _, shown in
                if shown { inPlayer?.pauseForQuestion() } else { inPlayer?.resumeAfterQuestion() }
            }
            .appSheet(isPresented: isShown, title: "Who's Watching?", systemImage: "person.2") {
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
