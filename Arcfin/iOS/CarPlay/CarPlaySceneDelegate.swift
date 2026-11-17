// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import CarPlay
import JellyfinAPI
import MediaEngine
import UIKit

/// Music in the car: what's been played, playlists, albums and what's downloaded, each a tab,
/// and the system's Now Playing with shuffle, repeat, favorite and Up Next. It plays through
/// the same player as the phone, so the queue, lock screen and remotes carry on as they are.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPTabBarTemplateDelegate,
                                  CPNowPlayingTemplateObserver {
    private var interface: CPInterfaceController?
    private let recent = CPListTemplate(title: String(localized: "Recently Played"), sections: [])
    private let playlists = CPListTemplate(title: String(localized: "Playlists"), sections: [])
    private let albums = CPListTemplate(title: String(localized: "Albums"), sections: [])
    private let downloaded = CPListTemplate(title: String(localized: "Downloaded"), sections: [])

    private var music: MusicPlayback { AppServices.music }
    private var player: MusicQueuePlayer { music.player }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        recent.tabImage = UIImage(systemName: "clock")
        playlists.tabImage = UIImage(systemName: "music.note.list")
        albums.tabImage = UIImage(systemName: "square.stack")
        downloaded.tabImage = UIImage(systemName: "arrow.down.circle")
        for list in [recent, playlists, albums, downloaded] {
            list.emptyViewTitleVariants = [String(localized: "Nothing Here Yet")]
        }
        let tabs = CPTabBarTemplate(templates: [recent, playlists, albums, downloaded])
        tabs.delegate = self
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
        setUpNowPlaying()
        watchProfile()
        watchSong()
        load(recent)
    }

    /// Signing in, out or switching profile on the phone shows that profile's music here.
    private func watchProfile() {
        withObservationTracking {
            _ = AppServices.authManager.state.credential?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, interface != nil else { return }
                for list in [recent, playlists, albums, downloaded] { load(list) }
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

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CPNowPlayingTemplate.shared.remove(self)
        interface = nil
    }

    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        if let list = selectedTemplate as? CPListTemplate { load(list) }
    }

    // MARK: Lists

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
            switch list {
            case recent: list.updateSections(await recentSections())
            case playlists: list.updateSections([CPListSection(items: await playlistItems())])
            case albums: list.updateSections([CPListSection(items: await albumItems())])
            default: list.updateSections([CPListSection(items: downloadedItems())])
            }
        }
    }

    private func show(_ message: String, in list: CPListTemplate) {
        list.emptyViewTitleVariants = [message]
        list.updateSections([])
    }

    private func recentSections() async -> [CPListSection] {
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
        let played = (try? await MusicAPI.call {
            try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: .datePlayed,
                                        ascending: false, filter: .init(playedOnly: true), limit: 40)
        })?.tracks ?? []
        return [CPListSection(items: [shuffle]), CPListSection(items: songItems(played))]
    }

    private func playlistItems() async -> [CPListItem] {
        let found = (try? await MusicAPI.call { try await $0.getMusicPlaylists(credential: $1, authHeader: $2) }) ?? []
        return found.prefix(CPListTemplate.maximumItemCount).map { playlist in
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
    }

    private func albumItems() async -> [CPListItem] {
        let found = (try? await MusicAPI.call {
            try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: nil, sort: .dateAdded,
                                        ascending: false, limit: 100)
        })?.albums ?? []
        return found.map { album in
            let item = CPListItem(text: album.name, detailText: album.albumArtist)
            item.accessoryType = .disclosureIndicator
            loadImage(MusicAPI.artworkURL(album, width: 200), into: item)
            item.handler = { [weak self] _, done in
                Task {
                    self?.push(title: album.name, songs: await MusicActions.albumSongs(album))
                    done()
                }
            }
            return item
        }
    }

    /// Saved albums, which play without a connection.
    private func downloadedItems() -> [CPListItem] {
        MusicDownloads.shared.albums.map { entry in
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
    }

    /// A playlist's or album's songs, with Shuffle first.
    private func push(title: String, songs: [MusicSong]) {
        let shuffle = CPListItem(text: String(localized: "Shuffle"), detailText: nil, image: UIImage(systemName: "shuffle"))
        shuffle.handler = { [weak self] _, done in
            MusicActions.shuffle(songs)
            self?.showNowPlaying()
            done()
        }
        let list = CPListTemplate(title: title, sections: [CPListSection(items: [shuffle]), CPListSection(items: songItems(songs))])
        interface?.pushTemplate(list, animated: true, completion: nil)
    }

    /// Choosing a song plays the list from there.
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

    nonisolated func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {}

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
