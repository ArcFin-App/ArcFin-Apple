// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import JellyfinAPI
import SwiftUI

/// Find a scene by what's said in it: the server searches its index of subtitle lines.
struct ArcsSearchView: View {
    let model: ArcsModel

    @Environment(AuthManager.self) private var authManager
    @State private var query = ""
    @State private var results: [ArcClip] = []
    @State private var searched = ""
    @State private var isSearching = false
    @State private var opened: [ArcClip]?

    private let client = ArcsClient()

    var body: some View {
        List {
            if results.isEmpty {
                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if !searched.isEmpty {
                    ContentUnavailableView.search(text: searched)
                        .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView {
                        Label("Search What's Said", systemImage: "text.bubble")
                    } description: {
                        Text("Type a line you remember, and Arcs finds the scene it's in. Your server builds this from subtitles, so titles without them can't be found.")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            ForEach(results) { clip in
                Button {
                    let index = results.firstIndex(of: clip) ?? 0
                    opened = Array(results[index...])
                } label: {
                    ArcsSearchRow(clip: clip)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Search Scenes")
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("A line from a scene"))
        .onSubmit(of: .search) { Task { await search() } }
        .task(id: query) {
            // A pause in typing searches; each new letter starts the wait again.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await search()
        }
        .screenBackground()
        .fullScreenCover(item: Binding(get: { opened.map(ArcsSearchOpened.init) }, set: { if $0 == nil { opened = nil } })) { list in
            ArcsCover(feed: .forYou, startingWith: list.clips)
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, text != searched, let (credential, header) = model.auth() else {
            if text.isEmpty { results = []; searched = "" }
            return
        }
        isSearching = true
        defer { isSearching = false }
        results = (try? await client.search(text, seconds: model.seconds, credential: credential, authHeader: header)) ?? []
        searched = text
    }
}

private struct ArcsSearchOpened: Identifiable {
    let clips: [ArcClip]
    var id: String { clips.first?.id ?? "" }
}

/// A search result: the title, which scene, and the line that matched.
private struct ArcsSearchRow: View {
    let clip: ArcClip
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() } else { DT.Color.backgroundTertiary }
            }
            .frame(width: 56, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: clip.seriesName ?? clip.name).font(.headline).lineLimit(1)
                if let line = ArcText.sceneLine(clip) {
                    Text(verbatim: line).font(.footnote).foregroundStyle(DT.Color.textSecondary).lineLimit(1)
                }
                if let matched = clip.matchedLine {
                    Text(verbatim: "\u{201C}\(matched)\u{201D}").font(.subheadline).italic().lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(DT.Color.accent)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var imageURL: URL? {
        guard let credential = authManager.state.credential else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: clip.titleID, tag: "", type: .primary,
                                            fillWidth: 120, token: credential.accessToken)
    }
}

/// Sends a scene to someone else on this server: it shows first in their Arcs, with a note.
struct ArcsSendSheet: View {
    let clip: ArcClip
    let model: ArcsModel

    @Environment(\.dismiss) private var dismiss
    @State private var people: [ArcPerson] = []
    @State private var loaded = false
    @State private var note = ""
    @State private var sendingTo: ArcPerson?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .onChange(of: note) { _, text in if text.count > 140 { note = String(text.prefix(140)) } }
                } footer: {
                    Text("\(clip.seriesName ?? clip.name) shows first in their Arcs, with your name.")
                }
                Section {
                    if !loaded {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if people.isEmpty {
                        Text("Add friends with their Arcs code to send them scenes.")
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    ForEach(people) { person in
                        Button { Task { await send(to: person) } } label: {
                            HStack {
                                Label { Text(verbatim: person.name) } icon: { Image(systemName: "person.crop.circle") }
                                Spacer()
                                if sendingTo == person { ProgressView() } else { Image(systemName: "paperplane").foregroundStyle(DT.Color.accent) }
                            }
                        }
                        .disabled(sendingTo != nil)
                    }
                    NavigationLink {
                        ArcsFriendsView()
                    } label: {
                        Label("Add Friends", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Send To")
                } footer: {
                    if let error { Text(verbatim: error).foregroundStyle(DT.Color.palette("F43F5E")) }
                }
            }
            .navigationTitle("Send Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                people = await model.people()
                loaded = true
            }
            // Back from adding someone: they're listed straight away.
            .onAppear { if loaded { Task { people = await model.people() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func send(to person: ArcPerson) async {
        sendingTo = person
        error = await model.send(clip, to: person, note: note)
        sendingTo = nil
        if error == nil { dismiss() }
    }
}
