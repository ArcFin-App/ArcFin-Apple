// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import CarPlay
import CoreMedia
import JellyfinAPI
import MediaEngine
import UIKit

/// Music in the car, laid out like the system's music app so something plays in a tap or two:
/// Home (Shuffle All, Favorites and Downloaded along the top, then rows of covers for what's
/// been played, played most and favorites), New (what was added lately), Radio (stations from
/// what's playing, favorite artists and genres) and Library (favorites, playlists, artists A to
/// Z, albums, songs, genres, downloaded), with Search at the top of Home and Library, then the
/// system's Now Playing with shuffle, repeat, favorite, Up Next and the album. Everything is
/// CarPlay's own templates, so a knob, a touchpad or the steering wheel's buttons move through
/// it as well as touch does. It plays through the same player as the phone, so the queue, lock
/// screen and remotes carry on.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPTabBarTemplateDelegate,
                                  CPNowPlayingTemplateObserver, CPSessionConfigurationDelegate {
    private var interface: CPInterfaceController?
    private let home = CPListTemplate(title: String(localized: "Home"), sections: [])
    private let new = CPListTemplate(title: String(localized: "New"), sections: [])
    private let radio = CPListTemplate(title: String(localized: "Radio"), sections: [])
    private let library = CPListTemplate(title: String(localized: "Library"), sections: [])
    private let searchTab = CPListTemplate(title: String(localized: "Search"), sections: [])
    /// The car decides how many tabs there can be; with only four, New's rows go on Home.
    private var hasNewTab: Bool { CPTabBarTemplate.maximumTabCount >= 5 }
    private var tabs: [CPListTemplate] { hasNewTab ? [home, new, radio, library, searchTab] : [home, radio, library, searchTab] }

    private lazy var search = CarPlaySearch(scene: self)
    private lazy var voice = CarPlayVoiceSearch { [weak self] term in await self?.search.pushResults(for: term) }
    /// Whether the car has the keyboard off (most do while driving).
    private var session: CPSessionConfiguration?

    private var music: MusicPlayback { AppServices.music }
    private var player: MusicQueuePlayer { music.player }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        session = CPSessionConfiguration(delegate: self)
        home.tabImage = UIImage(systemName: "house")
        new.tabImage = UIImage(systemName: "sparkles")
        radio.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")
        library.tabImage = UIImage(systemName: "square.stack")
        searchTab.tabImage = UIImage(systemName: "magnifyingglass")
        let bar = CPTabBarTemplate(templates: tabs)
        bar.delegate = self
        interfaceController.setRootTemplate(bar, animated: false, completion: nil)
        setUpNowPlaying()
        watchProfile()
        watchSong()
        tabs.forEach(load)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CPNowPlayingTemplate.shared.remove(self)
        interface = nil
    }

    nonisolated func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration,
                                          limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        MainActor.assumeIsolated { load(searchTab) }
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
                tabs.forEach(load)
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
            switch list {
            case home: list.updateSections(await homeSections() + (hasNewTab ? [] : await newSections()))
            case new: list.updateSections(await newSections())
            case radio: list.updateSections(await radioSections())
            case searchTab: list.updateSections(searchSections())
            default: list.updateSections(librarySections())
            }
        }
    }

    private func show(_ message: String, in list: CPListTemplate) {
        list.emptyViewTitleVariants = [message]
        list.updateSections([])
    }

    /// Shuffle All, Favorites and Downloaded along the top, then rows of covers; a cover plays
    /// (or opens) that one, the row's title opens the whole list.
    private func homeSections() async -> [CPListSection] {
        var buttons = [
            CPGridButton(titleVariants: [String(localized: "Shuffle All")], image: UIImage(systemName: "shuffle") ?? UIImage()) { [weak self] _ in
                Task {
                    let songs = (try? await MusicAPI.call {
                        try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: .random, limit: 200)
                    })?.tracks ?? []
                    if !songs.isEmpty { MusicActions.play(songs) }
                    self?.showNowPlaying()
                }
            },
            CPGridButton(titleVariants: [String(localized: "Favorites")], image: UIImage(systemName: "star") ?? UIImage()) { [weak self] _ in
                Task { await self?.pushFavorites() }
            },
        ]
        if !MusicDownloads.shared.isEmpty {
            buttons.append(CPGridButton(titleVariants: [String(localized: "Downloaded")],
                                        image: UIImage(systemName: "arrow.down.circle") ?? UIImage()) { [weak self] _ in
                self?.pushDownloaded()
            })
        }
        home.headerGridButtons = buttons
        async let played = songs(sort: .datePlayed, filter: .init(playedOnly: true))
        async let most = songs(sort: .playCount, filter: .init(playedOnly: true))
        async let favorites = songs(sort: .name, filter: .init(favoritesOnly: true), ascending: true)
        var rows: [CPListTemplateItem] = []
        if let row = songRow(String(localized: "Recently Played"), await played) { rows.append(row) }
        if let row = songRow(String(localized: "Most Played"), await most) { rows.append(row) }
        if let row = songRow(String(localized: "Favorite Songs"), await favorites) { rows.append(row) }
        return rows.isEmpty ? [] : [CPListSection(items: rows)]
    }

    /// Search by Voice and Search Music (typing, when the car allows the keyboard); recent
    /// searches below them run again.
    private func searchSections() -> [CPListSection] {
        let byVoice = CPListItem(text: String(localized: "Search by Voice"), detailText: nil, image: UIImage(systemName: "mic"))
        byVoice.handler = { [weak self] _, done in
            guard let self else { return done() }
            voice.start(in: interface)
            done()
        }
        let keyboardOff = session?.limitedUserInterfaces.contains(.keyboard) == true
        let open = CPListItem(text: String(localized: "Search Music"),
                              detailText: keyboardOff ? String(localized: "The keyboard is off while driving") : nil,
                              image: UIImage(systemName: "keyboard"))
        open.accessoryType = .disclosureIndicator
        open.handler = { [weak self] _, done in
            guard let self else { return done() }
            search.show(in: interface)
            done()
        }
        var sections = [CPListSection(items: [byVoice, open])]
        let recents = search.recents.map { term in
            let item = CPListItem(text: term, detailText: nil, image: UIImage(systemName: "clock.arrow.circlepath"))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, done in
                Task {
                    await self?.search.pushResults(for: term)
                    done()
                }
            }
            return item
        }
        if !recents.isEmpty {
            sections.append(CPListSection(items: recents, header: String(localized: "Recent Searches"), sectionIndexTitle: nil))
        }
        return sections
    }

    /// What was added lately: the newest albums as covers, then the newest songs.
    private func newSections() async -> [CPListSection] {
        async let added = albums(sort: .dateAdded)
        async let latest = songs(sort: .dateAdded)
        var sections: [CPListSection] = []
        if let row = albumRow(String(localized: "Latest Albums"), await added) { sections.append(CPListSection(items: [row])) }
        let newest = await latest
        if !newest.isEmpty {
            sections.append(CPListSection(items: songItems(newest), header: String(localized: "Latest Songs"), sectionIndexTitle: nil))
        }
        return sections
    }

    /// Stations: one from what's playing, then from the artists played most, then by genre.
    private func radioSections() async -> [CPListSection] {
        var sections: [CPListSection] = []
        if let song = player.current {
            let item = station(String(localized: "Station from \(song.name)"), detail: song.artistLine,
                               symbol: "dot.radiowaves.left.and.right", seed: song.id)
            loadImage(MusicAPI.artworkURL(song, width: 120), into: item)
            sections.append(CPListSection(items: [item]))
        }
        async let most = songs(sort: .playCount, filter: .init(playedOnly: true))
        async let genres = (try? await MusicAPI.call { try await $0.getMusicGenres(credential: $1, authHeader: $2, libraryId: nil) }) ?? []
        var seen = Set<String>()
        let artists = await most.compactMap(\.artists.first).filter { seen.insert($0.id).inserted }.prefix(8)
        if !artists.isEmpty {
            let items = artists.map { artist in
                station(artist.name, detail: String(localized: "Artist Station"), symbol: "music.microphone", seed: artist.id)
            }
            sections.append(CPListSection(items: Array(items), header: String(localized: "Your Artists"), sectionIndexTitle: nil))
        }
        let genreItems = await genres.prefix(20).map { genre in
            station(genre.name, detail: String(localized: "Genre Station"), symbol: "guitars", seed: genre.id)
        }
        if !genreItems.isEmpty {
            sections.append(CPListSection(items: Array(genreItems), header: String(localized: "Genres"), sectionIndexTitle: nil))
        }
        return sections
    }

    /// Songs like the seed (a song, artist or genre), playing at once.
    private func station(_ title: String, detail: String?, symbol: String, seed: String) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail, image: UIImage(systemName: symbol))
        item.handler = { [weak self] _, done in
            Task {
                await MusicActions.instantMix(from: seed)
                self?.showNowPlaying()
                done()
            }
        }
        return item
    }

    private func librarySections() -> [CPListSection] {
        func row(_ title: String, _ symbol: String, _ open: @escaping @MainActor () async -> Void) -> CPListItem {
            let item = CPListItem(text: title, detailText: nil, image: UIImage(systemName: symbol))
            item.accessoryType = .disclosureIndicator
            item.handler = { _, done in Task { await open(); done() } }
            return item
        }
        var items = [
            row(String(localized: "Favorites"), "star") { [weak self] in await self?.pushFavorites() },
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
            row(String(localized: "Genres"), "guitars") { [weak self] in await self?.pushGenres() },
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
        let row = CPListImageRowItem(text: title, elements: shown.map {
            CPListImageRowItemRowElement(image: Self.placeholder, title: $0.name, subtitle: $0.artistLine)
        }, allowsMultipleLines: false)
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
        let row = CPListImageRowItem(text: title, elements: shown.map {
            CPListImageRowItemRowElement(image: Self.placeholder, title: $0.name, subtitle: $0.albumArtist)
        }, allowsMultipleLines: false)
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
        let size = CPListImageRowItemRowElement.maximumImageSize
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.secondarySystemFill.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()

    private func loadImages(_ urls: [URL?], into row: CPListImageRowItem) {
        Task {
            let elements = row.elements
            for (element, url) in zip(elements, urls) {
                guard let url, let data = await URLSession.arcfin.imageData(from: url), let image = UIImage(data: data) else { continue }
                element.image = image
                // Handing the elements back is what redraws the row.
                row.elements = elements
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
                    self?.push(title: playlist.name, songs: await MusicActions.playlistSongs(playlist),
                               cover: MusicAPI.artworkURL(playlist, width: 400),
                               subtitle: playlist.songCount.map { String(localized: "\($0) songs") })
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
        // A to Z, with the letters down the side to jump through a long list.
        let letters = Dictionary(grouping: found) { artist -> String in
            guard let first = artist.name.first.map(String.init)?.uppercased(), first.first?.isLetter == true else { return "#" }
            return first
        }
        let sections = letters.keys.sorted { $0 == "#" ? false : $1 == "#" ? true : $0 < $1 }.map { letter in
            CPListSection(items: letters[letter, default: []].map { artist in
                let item = CPListItem(text: artist.name, detailText: nil)
                item.accessoryType = .disclosureIndicator
                loadImage(MusicAPI.artworkURL(artist, width: 200), into: item)
                item.handler = { [weak self] _, done in
                    Task {
                        await self?.openArtist(artist)
                        done()
                    }
                }
                return item
            }, header: letter, sectionIndexTitle: letter)
        }
        pushList(String(localized: "Artists"), sections)
    }

    func openArtist(_ artist: MusicArtist) async {
        pushAlbums(artist.name, await albums(sort: .year, filter: .init(artistId: artist.id)))
    }

    func openAlbum(_ album: MusicAlbum) async {
        await pushAlbum(album)
    }

    func play(_ songs: [MusicSong], from index: Int) {
        MusicActions.play(songs, from: index)
        showNowPlaying()
    }

    private func pushFavorites() async {
        push(title: String(localized: "Favorite Songs"), songs: await songs(sort: .name, filter: .init(favoritesOnly: true), ascending: true))
    }

    /// Each genre opens its albums.
    private func pushGenres() async {
        let genres = (try? await MusicAPI.call { try await $0.getMusicGenres(credential: $1, authHeader: $2, libraryId: nil) }) ?? []
        let items = genres.prefix(CPListTemplate.maximumItemCount).map { genre in
            let item = CPListItem(text: genre.name, detailText: nil, image: UIImage(systemName: "guitars"))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, done in
                Task {
                    guard let self else { return done() }
                    self.pushAlbums(genre.name, await self.albums(sort: .name, filter: .init(genreId: genre.id), ascending: true))
                    done()
                }
            }
            return item
        }
        pushList(String(localized: "Genres"), [CPListSection(items: Array(items))])
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
        push(title: album.name, songs: await MusicActions.albumSongs(album), cover: MusicAPI.artworkURL(album, width: 400),
             subtitle: album.albumArtist)
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
            let cover = entry.songs.first?.albumId.flatMap(MusicDownloads.shared.coverURL(albumID:))
            item.handler = { [weak self] _, done in
                self?.push(title: name, songs: songs, cover: cover, subtitle: entry.album?.albumArtist ?? songs.first?.artistLine)
                done()
            }
            return item
        }
        pushList(String(localized: "Downloaded"), [CPListSection(items: items)])
    }

    /// A list of songs; choosing one plays the list from there. An album or playlist has its
    /// cover, name, artist and Play and Shuffle at the top (iOS 26.4); otherwise Shuffle comes first.
    private func push(title: String, songs: [MusicSong], cover: URL? = nil, subtitle: String? = nil) {
        if #available(iOS 26.4, *), cover != nil || subtitle != nil {
            let play = CPButton(image: UIImage(systemName: "play.fill") ?? UIImage()) { [weak self] _ in
                guard !songs.isEmpty else { return }
                self?.play(songs, from: 0)
            }
            let shuffle = CPButton(image: UIImage(systemName: "shuffle") ?? UIImage()) { [weak self] _ in
                guard !songs.isEmpty else { return }
                MusicActions.shuffle(songs)
                self?.showNowPlaying()
            }
            let header = CPListTemplateDetailsHeader(thumbnail: CPThumbnailImage(image: Self.placeholder), title: title,
                                                     subtitle: subtitle, actionButtons: [play, shuffle])
            if let cover {
                Task {
                    let data: Data? = cover.isFileURL ? try? Data(contentsOf: cover) : await URLSession.arcfin.imageData(from: cover)
                    if let data, let image = UIImage(data: data) { header.thumbnail = CPThumbnailImage(image: image) }
                }
            }
            let list = CPListTemplate(title: title, listHeader: header, sections: [CPListSection(items: songItems(songs))],
                                      assistantCellConfiguration: nil)
            list.emptyViewTitleVariants = [String(localized: "Nothing Here Yet")]
            interface?.pushTemplate(list, animated: true, completion: nil)
            return
        }
        let shuffle = CPListItem(text: String(localized: "Shuffle"), detailText: nil, image: UIImage(systemName: "shuffle"))
        shuffle.handler = { [weak self] _, done in
            MusicActions.shuffle(songs)
            self?.showNowPlaying()
            done()
        }
        pushList(title, [CPListSection(items: [shuffle]), CPListSection(items: songItems(songs))])
    }

    func pushList(_ title: String, _ sections: [CPListSection], empty: String = String(localized: "Nothing Here Yet")) {
        let list = CPListTemplate(title: title, sections: sections)
        list.emptyViewTitleVariants = [empty]
        interface?.pushTemplate(list, animated: true, completion: nil)
    }

    private func songItems(_ songs: [MusicSong]) -> [CPListItem] {
        let shown = Array(songs.prefix(CPListTemplate.maximumItemCount))
        return shown.enumerated().map { index, song in
            let item = CPListItem(text: song.name, detailText: song.artistLine)
            item.isPlaying = player.current?.id == song.id
            if #available(iOS 26.4, *) {
                let playing = item.isPlaying && player.isPlaying
                item.playbackConfiguration = CPPlaybackConfiguration(
                    preferredPresentation: .audio, playbackAction: playing ? .pause : .play, elapsedTime: .zero,
                    duration: CMTime(seconds: song.duration ?? 0, preferredTimescale: 600))
            }
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

    func loadImage(_ url: URL?, into item: CPListItem) {
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
        // On iOS 27 the song keeps playing in a small player over the app's lists.
        if #available(iOS 27.0, *) { template.allowsMiniPlayer = true }
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
            AppServices.music.setShuffled(!player.queue.isShuffled)
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
                AppServices.music.jump(to: entry.id)
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
