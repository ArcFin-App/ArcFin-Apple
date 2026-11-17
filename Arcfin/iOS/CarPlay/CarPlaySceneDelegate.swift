// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import CarPlay
import JellyfinAPI
import MediaEngine
import UIKit

/// Music in the car, laid out like the system's music app: Listen Now (rows of covers for
/// what's been played, added and played most, and favorites) and Library (playlists,
/// artists, albums, songs, downloaded), then the system's Now Playing with shuffle, repeat,
/// favorite, Up Next and the album. Everything is CarPlay's own templates, so a knob, a
/// touchpad or the steering wheel's buttons move through it as well as touch does. It plays
/// through the same player as the phone, so the queue, lock screen and remotes carry on.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPTabBarTemplateDelegate,
                                  CPNowPlayingTemplateObserver {
    private var interface: CPInterfaceController?
    private let listenNow = CPListTemplate(title: String(localized: "Listen Now"), sections: [])
    private let library = CPListTemplate(title: String(localized: "Library"), sections: [])

    private var music: MusicPlayback { AppServices.music }
    private var player: MusicQueuePlayer { music.player }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        listenNow.tabImage = UIImage(systemName: "play.circle")
        library.tabImage = UIImage(systemName: "square.stack")
        let tabs = CPTabBarTemplate(templates: [listenNow, library])
        tabs.delegate = self
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
        setUpNowPlaying()
        watchProfile()
        watchSong()
        load(listenNow)
        load(library)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CPNowPlayingTemplate.shared.remove(self)
        interface = nil
    }

    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        if let list = selectedTemplate as? CPListTemplate { load(list) }
    }

    /// Signing in, out or switching profile on the phone shows that profile's music here.
    private func watchProfile() {
        withObservationTracking {
            _ = AppServices.authManager.state.credential?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, interface != nil else { return }
                load(listenNow)
                load(library)
                watchProfile()
            }
        }
    }

    /// The star follows the song that's playing.
    private func watchSong() {
        withObservationTracking {
            _ = player.current?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, interface != nil else { return }
                updateNowPlayingButtons()
                watchSong()
            }
        }
    }

    // MARK: Tabs

    private func load(_ list: CPListTemplate) {
        Task {
            // Started from the car, the app hasn't checked its stored sign-in yet.
            let auth = AppServices.authManager
            await auth.checkStoredAuthOnce()
            guard let credential = auth.state.credential else {
                show(String(localized: "Sign in to Arcfin on your iPhone"), in: list)
                return
            }
            // A profile with a PIN stays locked until it's entered on the phone.
            if !AppServices.hasPassedLock, await auth.pin(for: credential.id) != nil {
                show(String(localized: "Unlock Arcfin on your iPhone"), in: list)
                return
            }
            list.emptyViewTitleVariants = [String(localized: "Nothing Here Yet")]
            list.updateSections(list === listenNow ? await listenNowSections() : librarySections())
        }
    }

    private func show(_ message: String, in list: CPListTemplate) {
        list.emptyViewTitleVariants = [message]
        list.updateSections([])
    }

    /// Shuffle All, then rows of covers; a cover plays (or opens) that one, the row's title
    /// opens the whole list.
    private func listenNowSections() async -> [CPListSection] {
        let shuffle = CPListItem(text: String(localized: "Shuffle All"), detailText: nil, image: UIImage(systemName: "shuffle"))
        shuffle.handler = { [weak self] _, done in
            Task {
                let songs = (try? await MusicAPI.call {
                    try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: .random, limit: 200)
                })?.tracks ?? []
                if !songs.isEmpty { MusicActions.play(songs) }
                self?.showNowPlaying()
                done()
            }
        }
        async let played = songs(sort: .datePlayed, filter: .init(playedOnly: true))
        async let most = songs(sort: .playCount, filter: .init(playedOnly: true))
        async let favorites = songs(sort: .name, filter: .init(favoritesOnly: true), ascending: true)
        async let added = albums(sort: .dateAdded)
        var rows: [CPListTemplateItem] = [shuffle]
        if let row = songRow(String(localized: "Recently Played"), await played) { rows.append(row) }
        if let row = albumRow(String(localized: "Recently Added"), await added) { rows.append(row) }
        if let row = songRow(String(localized: "Most Played"), await most) { rows.append(row) }
        if let row = songRow(String(localized: "Favorite Songs"), await favorites) { rows.append(row) }
        return [CPListSection(items: rows)]
    }

    private func librarySections() -> [CPListSection] {
        func row(_ title: String, _ symbol: String, _ open: @escaping @MainActor () async -> Void) -> CPListItem {
            let item = CPListItem(text: title, detailText: nil, image: UIImage(systemName: symbol))
            item.accessoryType = .disclosureIndicator
            item.handler = { _, done in Task { await open(); done() } }
            return item
        }
        var items = [
            row(String(localized: "Playlists"), "music.note.list") { [weak self] in await self?.pushPlaylists() },
            row(String(localized: "Artists"), "music.microphone") { [weak self] in await self?.pushArtists() },
            row(String(localized: "Albums"), "square.stack") { [weak self] in
                guard let self else { return }
                pushAlbums(String(localized: "Albums"), await albums(sort: .name, ascending: true))
            },
            row(String(localized: "Songs"), "music.note") { [weak self] in
                guard let self else { return }
                push(title: String(localized: "Songs"), songs: await songs(sort: .name, ascending: true))
            },
        ]
        if !MusicDownloads.shared.isEmpty {
            items.append(row(String(localized: "Downloaded"), "arrow.down.circle") { [weak self] in self?.pushDownloaded() })
        }
        return [CPListSection(items: items)]
    }

    // MARK: Rows of covers

    private func songRow(_ title: String, _ songs: [MusicSong]) -> CPListImageRowItem? {
        guard !songs.isEmpty else { return nil }
        let shown = Array(songs.prefix(CPMaximumNumberOfGridImages))
        let row = CPListImageRowItem(text: title, images: shown.map { _ in Self.placeholder })
        loadImages(shown.map { MusicAPI.artworkURL($0, width: 240) }, into: row)
        row.listImageRowHandler = { [weak self] _, index, done in
            MusicActions.play(songs, from: index)
            self?.showNowPlaying()
            done()
        }
        row.handler = { [weak self] _, done in
            self?.push(title: title, songs: songs)
            done()
        }
        return row
    }

    private func albumRow(_ title: String, _ albums: [MusicAlbum]) -> CPListImageRowItem? {
        guard !albums.isEmpty else { return nil }
        let shown = Array(albums.prefix(CPMaximumNumberOfGridImages))
        let row = CPListImageRowItem(text: title, images: shown.map { _ in Self.placeholder })
        loadImages(shown.map { MusicAPI.artworkURL($0, width: 240) }, into: row)
        row.listImageRowHandler = { [weak self] _, index, done in
            Task {
                await self?.pushAlbum(shown[index])
                done()
            }
        }
        row.handler = { [weak self] _, done in
            self?.pushAlbums(title, albums)
            done()
        }
        return row
    }

    private static let placeholder: UIImage = {
        let size = CPListImageRowItem.maximumImageSize
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemFill.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()

    private func loadImages(_ urls: [URL?], into row: CPListImageRowItem) {
        Task {
            var images = row.gridImages
            for (index, url) in urls.enumerated() {
                guard let url, let data = await URLSession.arcfin.imageData(from: url), let image = UIImage(data: data) else { continue }
                images[index] = image
                row.update(images)
            }
        }
    }

    // MARK: Lists

    private func pushPlaylists() async {
        let found = (try? await MusicAPI.call { try await $0.getMusicPlaylists(credential: $1, authHeader: $2) }) ?? []
        let items = found.prefix(CPListTemplate.maximumItemCount).map { playlist in
            let item = CPListItem(text: playlist.name, detailText: playlist.songCount.map { String(localized: "\($0) songs") })
            item.accessoryType = .disclosureIndicator
            loadImage(MusicAPI.artworkURL(playlist, width: 200), into: item)
            item.handler = { [weak self] _, done in
                Task {
                    self?.push(title: playlist.name, songs: await MusicActions.playlistSongs(playlist))
                    done()
                }
            }
            return item
        }
        pushList(String(localized: "Playlists"), [CPListSection(items: Array(items))])
    }

    private func pushArtists() async {
        let found = (try? await MusicAPI.call {
            try await $0.getMusicArtists(credential: $1, authHeader: $2, libraryId: nil, limit: CPListTemplate.maximumItemCount)
        })?.artists ?? []
        let items = found.map { artist in
            let item = CPListItem(text: artist.name, detailText: nil)
            item.accessoryType = .disclosureIndicator
            loadImage(MusicAPI.artworkURL(artist, width: 200), into: item)
            item.handler = { [weak self] _, done in
                Task {
                    guard let self else { return done() }
                    self.pushAlbums(artist.name, await self.albums(sort: .year, filter: .init(artistId: artist.id)))
                    done()
                }
            }
            return item
        }
        pushList(String(localized: "Artists"), [CPListSection(items: items)])
    }

    private func pushAlbums(_ title: String, _ albums: [MusicAlbum]) {
        let items = albums.prefix(CPListTemplate.maximumItemCount).map { album in
            let item = CPListItem(text: album.name, detailText: album.albumArtist)
            item.accessoryType = .disclosureIndicator
            loadImage(MusicAPI.artworkURL(album, width: 200), into: item)
            item.handler = { [weak self] _, done in
                Task {
                    await self?.pushAlbum(album)
                    done()
                }
            }
            return item
        }
        pushList(title, [CPListSection(items: Array(items))])
    }

    private func pushAlbum(_ album: MusicAlbum) async {
        push(title: album.name, songs: await MusicActions.albumSongs(album))
    }

    /// Saved albums, which play without a connection.
    private func pushDownloaded() {
        let items = MusicDownloads.shared.albums.map { entry in
            let name = entry.album?.name ?? entry.songs.first?.albumName ?? String(localized: "Songs")
            let item = CPListItem(text: name, detailText: entry.album?.albumArtist ?? entry.songs.first?.artistLine)
            item.accessoryType = .disclosureIndicator
            if let id = entry.songs.first?.albumId, let url = MusicDownloads.shared.coverURL(albumID: id),
               let image = UIImage(contentsOfFile: url.path) {
                item.setImage(image)
            }
            let songs = entry.songs
            item.handler = { [weak self] _, done in
                self?.push(title: name, songs: songs)
                done()
            }
            return item
        }
        pushList(String(localized: "Downloaded"), [CPListSection(items: items)])
    }

    /// A list of songs with Shuffle first; choosing a song plays the list from there.
    private func push(title: String, songs: [MusicSong]) {
        let shuffle = CPListItem(text: String(localized: "Shuffle"), detailText: nil, image: UIImage(systemName: "shuffle"))
        shuffle.handler = { [weak self] _, done in
            MusicActions.shuffle(songs)
            self?.showNowPlaying()
            done()
        }
        pushList(title, [CPListSection(items: [shuffle]), CPListSection(items: songItems(songs))])
    }

    private func pushList(_ title: String, _ sections: [CPListSection]) {
        let list = CPListTemplate(title: title, sections: sections)
        list.emptyViewTitleVariants = [String(localized: "Nothing Here Yet")]
        interface?.pushTemplate(list, animated: true, completion: nil)
    }

    private func songItems(_ songs: [MusicSong]) -> [CPListItem] {
        let shown = Array(songs.prefix(CPListTemplate.maximumItemCount))
        return shown.enumerated().map { index, song in
            let item = CPListItem(text: song.name, detailText: song.artistLine)
            item.isPlaying = player.current?.id == song.id
            loadImage(MusicAPI.artworkURL(song, width: 120), into: item)
            item.handler = { [weak self] _, done in
                MusicActions.play(shown, from: index)
                self?.showNowPlaying()
                done()
            }
            return item
        }
    }

    private func songs(sort: MusicSort, filter: MusicFilter = .init(), ascending: Bool = false) async -> [MusicSong] {
        (try? await MusicAPI.call {
            try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: sort, ascending: ascending,
                                        filter: filter, limit: CPListTemplate.maximumItemCount)
        })?.tracks ?? []
    }

    private func albums(sort: MusicSort, filter: MusicFilter = .init(), ascending: Bool = false) async -> [MusicAlbum] {
        (try? await MusicAPI.call {
            try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: nil, sort: sort, ascending: ascending,
                                        filter: filter, limit: CPListTemplate.maximumItemCount)
        })?.albums ?? []
    }

    private func loadImage(_ url: URL?, into item: CPListItem) {
        guard let url else { return }
        Task {
            guard let data = await URLSession.arcfin.imageData(from: url), let image = UIImage(data: data) else { return }
            item.setImage(image)
        }
    }

    // MARK: Now Playing

    private func setUpNowPlaying() {
        let template = CPNowPlayingTemplate.shared
        template.isUpNextButtonEnabled = true
        template.upNextTitle = String(localized: "Up Next")
        template.isAlbumArtistButtonEnabled = true
        template.add(self)
        updateNowPlayingButtons()
    }

    private func updateNowPlayingButtons() {
        let isFavorite = player.current.map { MusicFavorites.shared.isFavorite($0.id, server: $0.isFavorite) } ?? false
        let favorite = CPNowPlayingImageButton(image: UIImage(systemName: isFavorite ? "star.fill" : "star") ?? UIImage()) { [weak self] _ in
            self?.music.favoriteCurrent()
            self?.updateNowPlayingButtons()
        }
        let shuffle = CPNowPlayingShuffleButton { [weak self] _ in
            guard let self else { return }
            player.setShuffled(!player.queue.isShuffled)
        }
        let repeatButton = CPNowPlayingRepeatButton { [weak self] _ in
            guard let self else { return }
            player.repeatMode = switch player.repeatMode {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([shuffle, repeatButton, favorite])
    }

    private func showNowPlaying() {
        guard let interface, interface.topTemplate !== CPNowPlayingTemplate.shared else { return }
        updateNowPlayingButtons()
        interface.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        MainActor.assumeIsolated { showUpNext() }
    }

    /// The album of the song that's playing.
    nonisolated func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        MainActor.assumeIsolated {
            guard let id = player.current?.albumId else { return }
            Task {
                guard let album = try? await MusicAPI.call({
                    try await $0.getMusicAlbum(credential: $1, authHeader: $2, albumId: id)
                }) else { return }
                await pushAlbum(album)
            }
        }
    }

    /// What's playing next; choosing one goes there.
    private func showUpNext() {
        let items = player.queue.upNext.prefix(CPListTemplate.maximumItemCount).map { entry in
            let item = CPListItem(text: entry.track.name, detailText: entry.track.artistLine)
            loadImage(MusicAPI.artworkURL(entry.track, width: 120), into: item)
            item.handler = { [weak self] _, done in
                self?.player.jump(to: entry.id)
                _ = self?.interface?.popTemplate(animated: true, completion: nil)
                done()
            }
            return item
        }
        let list = CPListTemplate(title: String(localized: "Up Next"), sections: [CPListSection(items: Array(items))])
        list.emptyViewTitleVariants = [String(localized: "Nothing Up Next")]
        interface?.pushTemplate(list, animated: true, completion: nil)
    }
}
