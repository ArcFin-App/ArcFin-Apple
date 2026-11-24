// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Watched and Favorite toggles for a poster's long-press menu. The change shows on the card
/// straight away (in Home's shelves, and through `onUpdate` in the grid that owns the card)
/// and is put back if the server refuses it; then the shelves whose membership it changes
/// (Continue Watching, Next Up, Favorites) are re-read.
struct ItemQuickActions: View {
    let item: MediaItem
    var onUpdate: ((MediaItem) -> Void)? = nil

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        let played = item.userData?.played ?? false
        let favorite = item.userData?.isFavorite ?? false

        Button {
            perform(changing: { data in
                data.played = !played
                data.playbackPositionTicks = 0
                data.playedPercentage = nil
                // A show's badge counts episodes left; nothing's left once it's all watched.
                data.unplayedItemCount = played ? nil : 0
            }) { client, cred, header in
                try await client.markWatched(credential: cred, authHeader: header, itemId: item.id, watched: !played)
            }
        } label: {
            Label(played ? "Mark as Unwatched" : "Mark as Watched", systemImage: played ? "eye.slash" : "checkmark")
        }
        let companion = ServerCompanion.shared
        if (item.userData?.playbackPositionTicks ?? 0) > 0, !played, companion.has("hidden") {
            // With the Arcfin Sync plugin: hidden on every device, keeping the place.
            Button {
                HapticManager.impact(.light)
                Task { _ = await companion.setHidden(true, itemID: item.id, from: .continueWatching, authManager: authManager) }
            } label: {
                Label("Hide from Continue Watching", systemImage: "eye.slash")
            }
        } else if (item.userData?.playbackPositionTicks ?? 0) > 0, !played {
            Button {
                perform(changing: { data in
                    data.playbackPositionTicks = 0
                    data.playedPercentage = nil
                }) { client, cred, header in
                    try await client.clearResumePosition(credential: cred, authHeader: header, itemId: item.id)
                }
            } label: {
                Label("Remove from Continue Watching", systemImage: "xmark.circle")
            }
        }
        if item.type == .episode, !played, let seriesID = item.seriesId, companion.has("hidden"),
           !companion.isHidden(seriesID, from: .nextUp) {
            Button {
                HapticManager.impact(.light)
                Task { _ = await companion.setHidden(true, itemID: seriesID, from: .nextUp, authManager: authManager) }
            } label: {
                Label("Hide Show from Next Up", systemImage: "forward.end")
            }
        }
        Button {
            perform(changing: { $0.isFavorite = !favorite }) { client, cred, header in
                try await client.markFavorite(credential: cred, authHeader: header, itemId: item.id, favorite: !favorite)
            }
        } label: {
            Label(favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: favorite ? "heart.slash" : "heart")
        }
        if [.movie, .episode, .series, .season].contains(item.type) {
            Button {
                PlaylistStore.shared.addingItem = item
            } label: {
                Label("Add to Playlist…", systemImage: "text.badge.plus")
            }
        }
        CopyItemMenu(item: item)
        EditTagsButton(item: item)
        EditMetadataButton(item: item)
    }

    private func perform(changing change: (inout UserData) -> Void,
                         _ action: @escaping (JellyfinMediaClient, ServerCredential, String) async throws -> Void) {
        guard case .authenticated(let cred) = authManager.state else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        HapticManager.impact(.light)
        let original = item
        var updated = item
        var data = updated.userData ?? UserData()
        change(&data)
        updated.userData = data
        show(updated)
        Task {
            do {
                try await action(JellyfinMediaClient(), cred, header)
            } catch {
                show(original)
            }
            await mediaRepo.refreshWatchState(credential: cred, authClient: authManager.authClient)
        }
    }

    private func show(_ item: MediaItem) {
        mediaRepo.applyUserData(of: item)
        onUpdate?(item)
    }
}
