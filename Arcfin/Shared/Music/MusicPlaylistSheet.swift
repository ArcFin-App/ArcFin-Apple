// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Adding songs to a music playlist, from any menu; the sheet is hosted once at the tab root.
@MainActor @Observable
final class MusicPlaylistEditor {
    static let shared = MusicPlaylistEditor()

    struct Request: Identifiable {
        let id = UUID()
        let songs: [MusicSong]
    }

    var request: Request?
    /// Goes up whenever a playlist changes here, so its page reloads.
    private(set) var changeCount = 0

    func add(_ songs: [MusicSong]) {
        guard !songs.isEmpty else { return }
        request = Request(songs: songs)
    }

    func addSongs(of album: MusicAlbum) {
        Task { add(await MusicActions.albumSongs(album)) }
    }

    func add(_ songs: [MusicSong], to playlist: MusicPlaylist) async throws {
        let ids = songs.map(\.id)
        try await MusicAPI.call { try await $0.addToPlaylist(credential: $1, authHeader: $2, playlistId: playlist.id, itemIds: ids) }
        changeCount += 1
    }

    func create(named name: String, with songs: [MusicSong]) async throws {
        let ids = songs.map(\.id)
        try await MusicAPI.call { try await $0.createMusicPlaylist(credential: $1, authHeader: $2, name: name, songIds: ids) }
        changeCount += 1
    }

    func remove(_ song: MusicSong, from playlist: MusicPlaylist) async {
        guard let entry = song.playlistEntryId else { return }
        _ = try? await MusicAPI.call {
            try await $0.removeFromPlaylist(credential: $1, authHeader: $2, playlistId: playlist.id, entryIds: [entry])
        }
        changeCount += 1
    }
}

/// "Add to Playlist…" for songs: a new playlist, or one of the profile's music playlists.
struct MusicAddToPlaylistButton: View {
    let songs: () async -> [MusicSong]

    var body: some View {
        Button("Add to Playlist…", systemImage: "text.badge.plus") {
            Task { MusicPlaylistEditor.shared.add(await songs()) }
        }
    }
}

struct MusicAddToPlaylistSheet: View {
    let songs: [MusicSong]
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [MusicPlaylist] = []
    @State private var newName = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New playlist", text: $newName)
                            .onSubmit(create)
                        Button("Create", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    }
                }
                if !playlists.isEmpty {
                    Section("Your Playlists") {
                        ForEach(playlists) { playlist in
                            Button { add(to: playlist) } label: {
                                HStack {
                                    Label { Text(verbatim: playlist.name) } icon: { Image(systemName: "music.note.list") }
                                        .foregroundStyle(DT.Color.textPrimary)
                                    Spacer()
                                    if let count = playlist.songCount {
                                        Text(verbatim: "\(count)").foregroundStyle(DT.Color.textSecondary)
                                    }
                                }
                            }
                            .disabled(busy)
                        }
                    }
                }
                if let errorMessage {
                    Text(verbatim: errorMessage).font(.footnote).foregroundStyle(DT.Color.palette("F43F5E"))
                }
            }
            .sheetTitle("Add to Playlist")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                playlists = (try? await MusicAPI.call { try await $0.getMusicPlaylists(credential: $1, authHeader: $2) }) ?? []
            }
        }
    }

    private func add(to playlist: MusicPlaylist) {
        run { try await MusicPlaylistEditor.shared.add(songs, to: playlist) }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        run { try await MusicPlaylistEditor.shared.create(named: name, with: songs) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do {
                try await work()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }
}
