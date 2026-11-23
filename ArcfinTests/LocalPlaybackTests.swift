// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import JellyfinAPI
import MediaEngine
import Persistence
@testable import Arcfin

@MainActor
struct LocalPlaybackTests {
    // MARK: Episode order

    private func episode(_ id: String, _ season: Int?, _ number: Int?) -> LocalEpisodeOrder.Episode {
        LocalEpisodeOrder.Episode(id: id, season: season, episode: number)
    }

    @Test func downloadedEpisodesGoInSeasonAndEpisodeOrder() {
        let all = [episode("s2e1", 2, 1), episode("s1e3", 1, 3), episode("s1e1", 1, 1)]
        let order = LocalEpisodeOrder.neighbours(of: episode("s1e3", 1, 3), in: all)
        #expect(order.previous == "s1e1")
        #expect(order.next == "s2e1")
    }

    @Test func theFirstAndLastHaveNothingBeforeOrAfter() {
        let all = [episode("a", 1, 1), episode("b", 1, 2)]
        #expect(LocalEpisodeOrder.neighbours(of: episode("a", 1, 1), in: all).previous == nil)
        #expect(LocalEpisodeOrder.neighbours(of: episode("b", 1, 2), in: all).next == nil)
    }

    @Test func specialsStayOutOfTheRunUnlessOneIsPlaying() {
        let all = [episode("special", 0, 1), episode("e1", 1, 1), episode("e2", 1, 2)]
        #expect(LocalEpisodeOrder.neighbours(of: episode("e1", 1, 1), in: all).previous == nil)
        #expect(LocalEpisodeOrder.neighbours(of: episode("special", 0, 1), in: all).next == "e1")
    }

    @Test func anEpisodeNotInTheListHasNoNeighbours() {
        let order = LocalEpisodeOrder.neighbours(of: episode("gone", 1, 5), in: [episode("e1", 1, 1)])
        #expect(order.next == nil && order.previous == nil)
    }

    // MARK: Saved streams

    private let detailJSON = """
    {"Id":"x","Name":"X","Type":"Episode","MediaSources":[{"Id":"src","Container":"mkv","MediaStreams":[
      {"Index":0,"Type":"Video","Codec":"hevc","VideoRange":"HDR","Width":3840,"Height":2160},
      {"Index":1,"Type":"Audio","Codec":"eac3","Language":"eng","DisplayTitle":"English 5.1","IsDefault":true},
      {"Index":2,"Type":"Audio","Codec":"aac","Language":"jpn","DisplayTitle":"Japanese"},
      {"Index":3,"Type":"Subtitle","Codec":"subrip","Language":"eng","IsForced":true},
      {"Index":4,"Type":"Subtitle","Codec":"subrip","Language":"fre","IsExternal":true,"DeliveryUrl":"/Videos/x/src/Subtitles/4/0/Stream.vtt"}
    ]}]}
    """

    @Test func savedDetailsKeepEachStreamsIndexLanguageAndFlags() throws {
        let saved = try #require(JellyfinMediaStream.savedStreams(fromItemDetail: Data(detailJSON.utf8)))
        #expect(saved.container == "mkv")
        #expect(saved.streams.map(\.index) == [0, 1, 2, 3, 4])
        let video = try #require(saved.streams.first { $0.type == "Video" })
        #expect(video.videoRange == "HDR" && video.height == 2160)
        let english = try #require(saved.streams.first { $0.index == 1 })
        #expect(english.language == "eng" && english.isDefault && english.displayTitle == "English 5.1")
        #expect(saved.streams.first { $0.index == 3 }?.isForced == true)
        #expect(saved.streams.first { $0.index == 4 }?.isExternal == true)
    }

    @Test func detailsWithoutStreamsGiveNone() {
        #expect(JellyfinMediaStream.savedStreams(fromItemDetail: Data("{\"Id\":\"x\"}".utf8)) == nil)
        #expect(JellyfinMediaStream.savedStreams(fromItemDetail: Data("not json".utf8)) == nil)
    }

    @Test func engineTracksTakeTheSavedNamesWhereTheyMatch() throws {
        let saved = try #require(JellyfinMediaStream.savedStreams(fromItemDetail: Data(detailJSON.utf8))).streams
        let sidecar = JellyfinMediaStream(index: 4, type: "Subtitle", language: "fre", isExternal: true)
        let tracks = LocalTracks.streams(
            saved: saved, sidecars: [sidecar],
            engineAudio: [AudioTrack(id: 1, displayName: "Track 1", language: "eng"), AudioTrack(id: 2, displayName: "Track 2")],
            engineSubtitles: [SubtitleTrack(id: 3, displayName: "Sub")])
        #expect(tracks.audio.map(\.displayTitle) == ["English 5.1", "Japanese"])
        #expect(tracks.subtitles.map(\.index) == [3, 4])
        #expect(tracks.subtitles.first?.isForced == true)
    }

    @Test func aConvertedDownloadListsOnlyWhatTheEngineFinds() {
        // A smaller copy keeps one audio track, numbered by its own file.
        let saved = [JellyfinMediaStream(index: 1, type: "Audio", language: "eng"),
                     JellyfinMediaStream(index: 2, type: "Audio", language: "jpn")]
        let tracks = LocalTracks.streams(saved: saved, sidecars: [],
                                         engineAudio: [AudioTrack(id: 7, displayName: "Japanese", language: "jpn")],
                                         engineSubtitles: [])
        #expect(tracks.audio.map(\.index) == [7])
        #expect(tracks.audio.first?.language == "jpn")
        #expect(tracks.subtitles.isEmpty)
    }

    @Test func sidecarFileNamesGiveTheirStreamIndex() {
        #expect(LocalTracks.sidecarIndex(fileName: "sub-12.vtt") == 12)
        #expect(LocalTracks.sidecarIndex(fileName: "poster.jpg") == nil)
        #expect(LocalTracks.sidecarIndex(fileName: "sub-x.vtt") == nil)
    }

    // MARK: Saving the position

    @Test func positionZeroIsNeverSavedBeforePlaybackStarts() {
        #expect(!DownloadPlaybackSource.hasStarted(atTicks: 0, durationTicks: 36_000_000_000, status: .playing))
        #expect(!DownloadPlaybackSource.hasStarted(atTicks: 50_000_000, durationTicks: 0, status: .playing))
        #expect(!DownloadPlaybackSource.hasStarted(atTicks: 50_000_000, durationTicks: 36_000_000_000, status: .loading))
        #expect(DownloadPlaybackSource.hasStarted(atTicks: 50_000_000, durationTicks: 36_000_000_000, status: .playing))
        #expect(DownloadPlaybackSource.hasStarted(atTicks: 50_000_000, durationTicks: 36_000_000_000, status: .paused))
    }

    // MARK: Reporting the position

    private let resumePoint: Int64 = 24_000_000_000

    @Test func beforePlaybackStartsTheResumePointIsReported() {
        for status: PlaybackStatus in [.idle, .loading, .paused, .playing, .failed("no stream")] {
            #expect(PlayerModel.reportablePosition(engineTicks: 0, status: status, trusted: false,
                                                   lastGood: nil, resumeFrom: resumePoint) == resumePoint)
        }
    }

    @Test func duringAReloadTheLastGoodPositionIsReported() {
        #expect(PlayerModel.reportablePosition(engineTicks: 0, status: .playing, trusted: false,
                                               lastGood: 30_000_000_000, resumeFrom: resumePoint) == 30_000_000_000)
        #expect(PlayerModel.reportablePosition(engineTicks: 0, status: .idle, trusted: true,
                                               lastGood: 30_000_000_000, resumeFrom: resumePoint) == 30_000_000_000)
    }

    @Test func whilePlayingOrPausedTheEnginesPositionIsReported() {
        #expect(PlayerModel.reportablePosition(engineTicks: 31_000_000_000, status: .playing, trusted: true,
                                               lastGood: 30_000_000_000, resumeFrom: resumePoint) == 31_000_000_000)
        #expect(PlayerModel.reportablePosition(engineTicks: 0, status: .paused, trusted: true,
                                               lastGood: 30_000_000_000, resumeFrom: resumePoint) == 0)
        #expect(!PlayerModel.positionIsReportable(status: .loading, trusted: true))
        #expect(!PlayerModel.positionIsReportable(status: .playing, trusted: false))
    }

    // MARK: Capabilities

    @Test func onlyTheServerOffersItsExtras() {
        let server = ServerPlaybackSource().capabilities
        #expect(server == .server)
        #expect(server.quality && server.syncPlay && server.sharePlay && server.casting && server.subtitleSearch)
        let file = FilePlaybackSource(url: URL(fileURLWithPath: "/tmp/movie.mkv"))
        #expect(file.capabilities == .local)
        let local = PlaybackCapabilities.local
        #expect(!local.quality && !local.versions && !local.syncPlay && !local.sharePlay && !local.casting)
        #expect(!local.subtitleSearch && !local.moreLikeThis && !local.rating && !local.personPages)
        #expect(!local.serverRemoteControl && !local.newWindow && !local.externalPlayer)
    }

    @Test func aDownloadOffersNoServerExtras() {
        let download = DownloadedItem(itemId: "d", name: "D", typeRaw: "Episode", seriesId: "show", seriesName: "Show",
                                      seasonNumber: 1, episodeNumber: 2, serverId: "s", serverBaseURL: "https://example.com",
                                      userId: "u", videoFileName: "video.mkv")
        let source = DownloadPlaybackSource(downloadedItem: download)
        #expect(source.capabilities == .local)
        #expect(source.isLocal && source.tracksComeFromEngine)
        #expect(source.item.type == .episode && source.item.parentIndexNumber == 1 && source.item.indexNumber == 2)
        #expect(source.download(for: "d") === download)
    }

    @Test func aPickedFileAndAServerAgreeOnWhatIsLocal() {
        #expect(!ServerPlaybackSource().isLocal)
        let file = FilePlaybackSource(url: URL(fileURLWithPath: "/tmp/movie.mkv"))
        #expect(file.isLocal && file.tracksComeFromEngine)
        #expect(file.item.name == "movie")
    }

    @Test func aLocalFileStaysOnAetherUnlessVLCIsPicked() {
        let file = FilePlaybackSource(url: URL(fileURLWithPath: "/tmp/movie.mkv"))
        #expect(file.engine(for: .auto) == .aether)
        #expect(file.engine(for: .avFoundation) == .aether)
        #expect(file.engine(for: .aether) == .aether)
        #expect(file.engine(for: .vlc) == .vlc)
        #expect(ServerPlaybackSource().engine(for: .avFoundation) == .avFoundation)
    }
}
