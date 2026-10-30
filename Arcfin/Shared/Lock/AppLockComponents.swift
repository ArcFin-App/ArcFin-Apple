// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// A profile in the lock screen's picker: its picture or initials, a lock when it has a PIN,
/// and a ring around the active one.
struct ProfileLockTile: View {
    let profile: ServerCredential
    let isActive: Bool
    let hasPIN: Bool
    let tileWidth: CGFloat
    let avatarSize: CGFloat

    private var initials: String {
        profile.displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let tag = profile.userImageTag {
            let url = JellyfinMediaClient.userImageURL(baseURL: profile.baseURL, userID: profile.userID, tag: tag, fillWidth: 200, token: profile.accessToken)
            CachedAsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    avatarInitials
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
        } else {
            avatarInitials
        }
    }

    private var avatarInitials: some View {
        Text(initials)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
    }

    var body: some View {
        let ringColor: Color = isActive ? DT.Color.accent : .clear

        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [DT.Color.accent, DT.Color.accentDeep],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: avatarSize, height: avatarSize)
                    avatarContent
                }
                .overlay(Circle().stroke(ringColor, lineWidth: 3))

                if hasPIN {
                    Image(systemName: "lock.fill")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Circle().fill(DT.Color.backgroundSecondary))
                }
            }

            Text(profile.displayName)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            Text(profile.baseURL.host ?? "")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1)
        }
        .frame(width: tileWidth)
    }
}

/// The lock screen's greeting above the profile picker.
struct AppLockGreeting: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Welcome to Arcfin")
                .font(.system(.title, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Please select your profile to continue")
                .font(.system(.subheadline))
                .foregroundStyle(DT.Color.textSecondary)
        }
    }
}
