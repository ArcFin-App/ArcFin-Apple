// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Shown in place of the app outside the hours the profile's parental controls allow. The
/// server refuses the profile's requests then too; this says why, and when it opens again.
struct AccessScheduleView: View {
    var onSwitchProfile: () -> Void

    @Environment(AuthManager.self) private var authManager
    private var rules: ProfileRules { .shared }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 52))
                .foregroundStyle(DT.Color.accent)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Not Available Right Now")
                    .font(.title2.bold())
                    .foregroundStyle(DT.Color.textPrimary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if !rules.policy.accessSchedules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allowed times")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DT.Color.textSecondary)
                    ForEach(Array(rules.policy.accessSchedules.enumerated()), id: \.offset) { _, schedule in
                        Label(ProfileRules.describe(schedule), systemImage: "clock")
                            .font(.callout)
                            .foregroundStyle(DT.Color.textPrimary)
                    }
                }
                .frame(maxWidth: 340, alignment: .leading)
                .padding(16)
                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer()
            if authManager.profiles.count > 1 {
                Button(action: onSwitchProfile) {
                    Text("Switch Profile").font(.headline).frame(maxWidth: 340, minHeight: 30)
                }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .screenBackground()
    }

    private var message: String {
        let name = rules.profile?.name ?? String(localized: "This profile")
        guard let next = rules.nextAllowedTime() else {
            return String(localized: "\(name) can't use this server at the moment.")
        }
        let when = Calendar.current.isDate(next, inSameDayAs: Date())
            ? next.formatted(date: .omitted, time: .shortened)
            : next.formatted(.dateTime.weekday(.wide).hour().minute())
        return String(localized: "\(name) can watch again from \(when).")
    }
}
