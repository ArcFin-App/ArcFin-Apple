// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Watched and Favorite toggles for a poster's long-press menu. The shelves are driven by
/// MediaRepository, so a successful change forces a reload to keep their badges and rows
/// (e.g. Continue Watching) consistent with the server.
struct ItemQuickActions: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        let played = item.userData?.played ?? false
        let favorite = item.userData?.isFavorite ?? false

        Button {
            perform { client, cred, header in
                _ = try? await client.markWatched(credential: cred, authHeader: header, itemId: item.id, watched: !played)
            }
        } label: {
            Label(played ? "Mark Unwatched" : "Mark Watched", systemImage: played ? "eye.slash" : "eye")
        }
        Button {
            perform { client, cred, header in
                _ = try? await client.markFavorite(credential: cred, authHeader: header, itemId: item.id, favorite: !favorite)
            }
        } label: {
            Label(favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: favorite ? "heart.slash" : "heart")
        }
    }

    private func perform(_ action: @escaping (JellyfinMediaClient, ServerCredential, String) async -> Void) {
        guard case .authenticated(let cred) = authManager.state else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        HapticManager.impact(.light)
        Task {
            await action(JellyfinMediaClient(), cred, header)
            await mediaRepo.load(credential: cred, authClient: authManager.authClient, force: true)
        }
    }
}
