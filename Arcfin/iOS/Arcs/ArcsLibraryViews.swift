// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import JellyfinAPI
import SwiftUI

/// The scenes this person liked, newest first, three to a row; one opens them as a feed.
struct ArcsLikedView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var clips: [ArcClip] = []
    @State private var cursor: String?
    @State private var loaded = false
    @State private var failed = false
    @State private var opened: [ArcClip]?

    private let client = ArcsClient()
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 3)]

    var body: some View {
        Group {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if clips.isEmpty {
                ContentUnavailableView {
                    Label(failed ? "Couldn't Load Liked Scenes" : "No Liked Scenes", systemImage: "heart")
                } description: {
                    failed ? Text("Couldn't reach your server. Check your connection, then try again.")
                           : Text("Double-tap a scene in Arcs to like it, and it shows here.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(clips) { clip in
                            Button {
                                let index = clips.firstIndex(of: clip) ?? 0
                                opened = Array(clips[index...])
                            } label: {
                                ArcsClipTile(clip: clip)
                            }
                            .buttonStyle(.plain)
                            .task { if clip == clips.last { await loadMore() } }
                        }
                    }
                }
            }
        }
        .navigationTitle("Liked Scenes")
        .toolbar(.visible, for: .navigationBar)
        .screenBackground()
        .task { if !loaded { await loadMore() } }
        .fullScreenCover(item: Binding(get: { opened.map(OpenedClips.init) }, set: { if $0 == nil { opened = nil } })) { list in
            ArcsCover(feed: .liked, startingWith: list.clips)
        }
    }

    private func loadMore() async {
        guard let credential = authManager.state.credential else { return }
        if loaded && cursor == nil { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        do {
            let page = try await client.feed(.liked, count: 30, cursor: cursor, spoilerSafe: false, seconds: 30,
                                             credential: credential, authHeader: header)
            let known = Set(clips.map(\.id))
            clips.append(contentsOf: page.clips.filter { !known.contains($0.id) })
            cursor = page.cursor
        } catch {
            failed = clips.isEmpty
        }
        loaded = true
    }
}

private struct OpenedClips: Identifiable {
    let clips: [ArcClip]
    var id: String { clips.first?.id ?? "" }
}

/// A liked scene: its title's poster, with the scene's line over the foot.
struct ArcsClipTile: View {
    let clip: ArcClip
    @Environment(AuthManager.self) private var authManager

    private var imageURL: URL? {
        guard let credential = authManager.state.credential else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: clip.titleID, tag: "", type: .primary,
                                            fillWidth: 300, token: credential.accessToken)
    }

    var body: some View {
        CachedAsyncImage(url: imageURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
        }
        .aspectRatio(2 / 3, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: clip.seriesName ?? clip.name).font(.caption.weight(.bold)).lineLimit(1)
                if let line = ArcText.sceneLine(clip) { Text(verbatim: line).font(.caption2).lineLimit(1) }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.7), radius: 4)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Titles kept out of Arcs: hidden, shown less, or skipped for now. Each can come back.
struct ArcsHiddenView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var titles: [ArcHiddenTitle] = []
    @State private var loaded = false

    private let client = ArcsClient()

    var body: some View {
        List {
            if loaded && titles.isEmpty {
                ContentUnavailableView("No Hidden Titles", systemImage: "eye",
                                       description: Text("Titles you hide in Arcs, or ask to see less of, show here."))
            }
            ForEach(titles) { title in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title.name)
                        Text(kindLabel(title)).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show Again") { Task { await unhide(title) } }
                        .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Hidden Titles")
        .toolbar(.visible, for: .navigationBar)
        .overlay { if !loaded { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func kindLabel(_ title: ArcHiddenTitle) -> LocalizedStringResource {
        switch title.kind {
        case "fewer":  "Shown less"
        case "notNow": title.until.map { "Back \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Not now"
        default:       "Hidden"
        }
    }

    private func load() async {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        titles = (try? await client.hidden(credential: credential, authHeader: header)) ?? titles
        loaded = true
    }

    private func unhide(_ title: ArcHiddenTitle) async {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        try? await client.unhide(title.id, credential: credential, authHeader: header)
        titles.removeAll { $0.id == title.id }
    }
}
