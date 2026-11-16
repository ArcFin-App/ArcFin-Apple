// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Music decoding")
struct MusicDecodingTests {

    private func items(_ json: String) throws -> [MusicItemResponse] {
        try JellyfinMediaClient.decodeMusicPage(Data(json.utf8)).items
    }

    @Test("An album keeps its artists, year, art and track count")
    func album() throws {
        let album = try #require(try items("""
            {"Items":[{"Id":"a1","Name":"Blue","AlbumArtist":"Joni Mitchell",\
            "AlbumArtists":[{"Id":"r1","Name":"Joni Mitchell"}],"ProductionYear":1971,\
            "ImageTags":{"Primary":"tag1"},"ChildCount":10,"Genres":["Folk"],"UserData":{"IsFavorite":true}}],\
            "TotalRecordCount":1}
            """).first).asAlbum
        #expect(album == MusicAlbum(id: "a1", name: "Blue", albumArtist: "Joni Mitchell",
                                    albumArtists: [MusicArtistRef(id: "r1", name: "Joni Mitchell")],
                                    productionYear: 1971, primaryImageTag: "tag1", trackCount: 10,
                                    genres: ["Folk"], isFavorite: true))
    }

    @Test("A track keeps its disc, number, album and artists")
    func track() throws {
        let track = try #require(try items("""
            {"Items":[{"Id":"t1","Name":"River","AlbumId":"a1","Album":"Blue","AlbumArtist":"Joni Mitchell",\
            "ArtistItems":[{"Id":"r1","Name":"Joni Mitchell"},{"Id":"r2","Name":"Guest"}],\
            "IndexNumber":7,"ParentIndexNumber":2,"RunTimeTicks":2400000000,"AlbumPrimaryImageTag":"tag1",\
            "UserData":{"PlayCount":3},"HasLyrics":true}]}
            """).first).asTrack
        #expect(track.trackNumber == 7)
        #expect(track.discNumber == 2)
        #expect(track.albumName == "Blue")
        #expect(track.albumPrimaryImageTag == "tag1")
        #expect(track.artistLine == "Joni Mitchell, Guest")
        #expect(track.duration == 240)
        #expect(track.playCount == 3)
        #expect(track.hasLyrics)
    }

    @Test("A track with no artists of its own uses the album's")
    func artistFallback() {
        #expect(MusicSong(id: "t", name: "x", albumArtist: "Various Artists").artistLine == "Various Artists")
        #expect(MusicSong(id: "t", name: "x").artistLine == nil)
    }

    @Test("An artist keeps its bio and backdrop")
    func artist() throws {
        let artist = try #require(try items("""
            {"Items":[{"Id":"r1","Name":"Joni Mitchell","Overview":"Canadian.","BackdropImageTags":["b1"],\
            "ImageTags":{"Primary":"p1"}}]}
            """).first).asArtist
        #expect(artist.overview == "Canadian.")
        #expect(artist.primaryImageTag == "p1")
        #expect(artist.backdropImageTags == ["b1"])
    }

    @Test("Synced lyrics follow the position")
    func syncedLyrics() throws {
        let lyrics = try JellyfinMediaClient.decodeLyrics(Data("""
            {"Metadata":{},"Lyrics":[{"Text":"One","Start":0},{"Text":"Two","Start":50000000},\
            {"Text":"Three","Start":120000000}]}
            """.utf8))
        #expect(lyrics.isSynced)
        #expect(lyrics.lines.map(\.start) == [0, 5, 12])
        #expect(lyrics.lineIndex(at: 0) == 0)
        #expect(lyrics.lineIndex(at: 6) == 1)
        #expect(lyrics.lineIndex(at: 60) == 2)
    }

    @Test("Lyrics without times aren't synced")
    func plainLyrics() throws {
        let lyrics = try JellyfinMediaClient.decodeLyrics(Data(#"{"Lyrics":[{"Text":"One"},{"Text":"Two"}]}"#.utf8))
        #expect(!lyrics.isSynced)
        #expect(lyrics.lineIndex(at: 3) == nil)
        #expect(lyrics.lines.map(\.text) == ["One", "Two"])
    }

    private static let credential = ServerCredential(baseURL: URL(string: "http://server:8096")!, userID: "u1",
                                                     accessToken: "tok", displayName: "Home")

    @Test("A container AVFoundation plays streams as is, with its extension in the path",
          arguments: [("flac", "stream.flac"), ("mp3", "stream.mp3"), ("mov,mp4,m4a,3gp,3g2,mj2", "stream.m4a")])
    func directStream(container: String, file: String) throws {
        let url = try #require(JellyfinMediaClient().audioStreamURL(credential: Self.credential, deviceId: "d",
                                                                    trackId: "t", container: container))
        #expect(url.path == "/Audio/t/\(file)")
        #expect(url.query?.contains("static=true") == true)
    }

    @Test("Anything else is made into MP3", arguments: ["ogg", "ape", nil] as [String?])
    func transcoded(container: String?) throws {
        let url = try #require(JellyfinMediaClient().audioStreamURL(credential: Self.credential, deviceId: "d",
                                                                    trackId: "t", container: container))
        #expect(url.path == "/Audio/t/stream.mp3")
        #expect(url.query?.contains("audioCodec=mp3") == true)
        #expect(url.query?.contains("static") == false)
    }

    @Test("A quality cap converts even a file AVFoundation plays, at that rate")
    func cappedStream() throws {
        let url = try #require(JellyfinMediaClient().audioStreamURL(credential: Self.credential, deviceId: "d",
                                                                    trackId: "t", container: "flac", bitrateCap: 128_000))
        #expect(url.path == "/Audio/t/stream.mp3")
        #expect(url.query?.contains("audioBitRate=128000") == true)
        #expect(url.query?.contains("static") == false)
    }

    @Test("A song's container is decoded")
    func containerDecoded() throws {
        let json = #"{"Items":[{"Id":"s","Name":"x","Container":"flac"}],"TotalRecordCount":1}"#
        let page = try JellyfinMediaClient.decodeMusicPage(Data(json.utf8))
        #expect(page.items.first?.asTrack.container == "flac")
    }

    @Test("A search splits into artists, albums and songs")
    func searchSplits() throws {
        let json = #"{"Items":[{"Id":"a","Name":"Band","Type":"MusicArtist"},{"Id":"b","Name":"Record","Type":"MusicAlbum"},{"Id":"c","Name":"Tune","Type":"Audio"},{"Id":"d","Name":"Film","Type":"Movie"}]}"#
        let results = JellyfinMediaClient.searchResults(try JellyfinMediaClient.decodeMusicPage(Data(json.utf8)).items)
        #expect(results.artists.map(\.id) == ["a"])
        #expect(results.albums.map(\.id) == ["b"])
        #expect(results.songs.map(\.id) == ["c"])
    }

    @Test("Items sent to play are songs only when every one is, in the order sent")
    func songsInOrder() throws {
        let json = #"{"Items":[{"Id":"b","Name":"B","Type":"Audio"},{"Id":"a","Name":"A","Type":"Audio"}]}"#
        let items = try JellyfinMediaClient.decodeMusicPage(Data(json.utf8)).items
        #expect(JellyfinMediaClient.songs(items, inOrder: ["a", "b"])?.map(\.id) == ["a", "b"])
        let mixed = #"{"Items":[{"Id":"a","Name":"A","Type":"Audio"},{"Id":"m","Name":"M","Type":"Movie"}]}"#
        #expect(JellyfinMediaClient.songs(try JellyfinMediaClient.decodeMusicPage(Data(mixed.utf8)).items, inOrder: ["a", "m"]) == nil)
    }
}
