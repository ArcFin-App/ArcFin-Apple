// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import JellyfinAPI
import SwiftUI

/// A title page's Best Scenes: the scenes people on this server liked most, or its best
/// moments when too few have. Opens them in Arcs.
struct ArcsBestScenes: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @AppStorage(ArcsSettings.spoilerSafeKey) private var spoilerSafe = true
    @State private var clips: [ArcClip] = []
    @State private var opened: [ArcClip]?

    private var titleID: String { item.type == .episode ? (item.seriesId ?? item.id) : item.id }
    private var available: Bool {
        authManager.arcfinSyncStatus?.isOn("arcs") == true && [.movie, .series, .episode].contains(item.type)
    }

    var body: some View {
        Group {
            if available, !clips.isEmpty {
                ShelfRow(title: "Best Scenes") {
                    ForEach(clips) { clip in
                        Button {
                            let index = clips.firstIndex(of: clip) ?? 0
                            opened = Array(clips[index...])
                        } label: {
                            ArcsSceneTile(clip: clip, backdropID: titleID)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: titleID) { await load() }
        .fullScreenCover(item: Binding(get: { opened.map(ArcsOpenedScenes.init) }, set: { if $0 == nil { opened = nil } })) { list in
            ArcsCover(feed: .forYou, startingWith: list.clips)
        }
    }

    private func load() async {
        guard available, let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        clips = (try? await ArcsClient().top(itemID: titleID, spoilerSafe: spoilerSafe, credential: credential, authHeader: header)) ?? []
    }
}

private struct ArcsOpenedScenes: Identifiable {
    let clips: [ArcClip]
    var id: String { clips.first?.id ?? "" }
}

/// One scene: the title's backdrop, which scene it is, and its likes.
private struct ArcsSceneTile: View {
    let clip: ArcClip
    let backdropID: String
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        CachedAsyncImage(url: imageURL) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFill() } else { DT.Color.backgroundTertiary }
        }
        .frame(width: 240, height: 135)
        .overlay {
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 2) {
                if clip.isColdOpen {
                    Text("Cold Open").font(.caption2.weight(.bold)).foregroundStyle(DT.Color.accent)
                }
                Text(verbatim: ArcText.sceneLine(clip) ?? clip.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                if clip.likeCount > 0 {
                    Label("\(clip.likeCount)", systemImage: "heart.fill").font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "play.fill").font(.caption).foregroundStyle(.white)
                .frame(width: 26, height: 26).glassEffect(.regular, in: Circle()).padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var imageURL: URL? {
        guard let credential = authManager.state.credential else { return nil }
        // An episode's own still when it's from one episode; otherwise the title's backdrop.
        let id = clip.isEpisode ? clip.itemId : backdropID
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: id, tag: "", type: clip.isEpisode ? .primary : .backdrop,
                                            fillWidth: 480, token: credential.accessToken)
    }
}
