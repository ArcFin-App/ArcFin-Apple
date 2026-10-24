// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// A profile's Jellyfin picture, or its initials on the accent colour when it has none.
struct ProfileAvatar: View {
    let profile: ServerCredential
    var size: CGFloat = 40

    private var initials: String {
        profile.displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }

    var body: some View {
        ZStack {
            Circle().fill(DT.Color.accent)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(DT.Color.onAccent)
            if let tag = profile.userImageTag {
                CachedAsyncImage(url: JellyfinMediaClient.userImageURL(
                    baseURL: profile.baseURL, userID: profile.userID, tag: tag,
                    fillWidth: Int(size * 3), token: profile.accessToken)) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
