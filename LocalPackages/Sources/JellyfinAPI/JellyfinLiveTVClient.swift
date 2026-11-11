// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Live TV models

public struct LiveTVChannel: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    /// The tuner or M3U channel number, e.g. "101" or "4.1".
    public var number: String?
    public var primaryImageTag: String?
    public var isFavorite: Bool
    public var currentProgram: LiveTVProgram?

    public init(id: String, name: String, number: String? = nil, primaryImageTag: String? = nil,
                isFavorite: Bool = false, currentProgram: LiveTVProgram? = nil) {
        self.id = id; self.name = name; self.number = number
        self.primaryImageTag = primaryImageTag; self.isFavorite = isFavorite
        self.currentProgram = currentProgram
    }

    /// The channel as the player and Now Playing see it.
    public var mediaItem: MediaItem {
        MediaItem(id: id, name: name, overview: currentProgram?.overview, type: .tvChannel,
                  primaryImageTag: primaryImageTag, userData: UserData(isFavorite: isFavorite))
    }
}

public struct LiveTVProgram: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let channelId: String
    public var channelName: String?
    public var name: String
    public var episodeTitle: String?
    public var overview: String?
    public var startDate: Date
    public var endDate: Date
    public var isSeries: Bool
    public var isMovie: Bool
    public var isNews: Bool
    public var isKids: Bool
    public var isSports: Bool
    public var isLive: Bool
    public var isPremiere: Bool
    public var isNew: Bool
    public var officialRating: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    /// Set when a recording of just this showing is scheduled.
    public var timerId: String?
    /// Set when the series it belongs to is being recorded.
    public var seriesTimerId: String?
    public var primaryImageTag: String?

    public init(id: String, channelId: String, channelName: String? = nil, name: String, episodeTitle: String? = nil,
                overview: String? = nil, startDate: Date, endDate: Date, isSeries: Bool = false, isMovie: Bool = false,
                isNews: Bool = false, isKids: Bool = false, isSports: Bool = false, isLive: Bool = false,
                isPremiere: Bool = false, isNew: Bool = false, officialRating: String? = nil,
                seasonNumber: Int? = nil, episodeNumber: Int? = nil, timerId: String? = nil,
                seriesTimerId: String? = nil, primaryImageTag: String? = nil) {
        self.id = id; self.channelId = channelId; self.channelName = channelName; self.name = name
        self.episodeTitle = episodeTitle; self.overview = overview
        self.startDate = startDate; self.endDate = endDate
        self.isSeries = isSeries; self.isMovie = isMovie; self.isNews = isNews; self.isKids = isKids
        self.isSports = isSports; self.isLive = isLive; self.isPremiere = isPremiere; self.isNew = isNew
        self.officialRating = officialRating; self.seasonNumber = seasonNumber; self.episodeNumber = episodeNumber
        self.timerId = timerId; self.seriesTimerId = seriesTimerId; self.primaryImageTag = primaryImageTag
    }

    public func isAiring(at date: Date = .now) -> Bool { startDate <= date && date < endDate }

    /// How far through it is, 0 to 1.
    public func progress(at date: Date = .now) -> Double {
        let length = endDate.timeIntervalSince(startDate)
        guard length > 0 else { return 0 }
        return min(max(date.timeIntervalSince(startDate) / length, 0), 1)
    }
}

/// A recording on the server: finished, or still being recorded.
public struct LiveTVRecording: Sendable, Identifiable, Equatable, Hashable {
    public var item: MediaItem
    public var channelName: String?
    public var startDate: Date?
    public var isRecording: Bool

    public var id: String { item.id }
}

public struct LiveTVTimer: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var programId: String?
    public var channelId: String?
    public var channelName: String?
    public var name: String
    public var startDate: Date
    public var endDate: Date
    /// "New", "InProgress", "Completed", "Cancelled", "ConflictedOk", "ConflictedNotOk" or "Error".
    public var status: String
    public var seriesTimerId: String?
    public var episodeTitle: String?

    public var isRecording: Bool { status == "InProgress" }
    public var hasProblem: Bool { status == "ConflictedNotOk" || status == "Error" }
}

public struct LiveTVSeriesTimer: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var channelName: String?
    public var recordAnyChannel: Bool
    public var recordAnyTime: Bool
    public var recordNewOnly: Bool
    public var imageItemId: String?
    public var imageTag: String?
}

// MARK: - Live TV requests

extension JellyfinMediaClient {

    /// GET /LiveTv/Channels with what's on each now, in the server's channel order, a page at
    /// a time: an IPTV playlist can hold tens of thousands.
    public func getLiveTVChannels(credential: ServerCredential, authHeader: String, startIndex: Int = 0,
                                  limit: Int = 200, favoritesOnly: Bool = false) async throws -> (channels: [LiveTVChannel], total: Int) {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveTv/Channels"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "userId", value: credential.userID),
            .init(name: "startIndex", value: "\(startIndex)"),
            .init(name: "limit", value: "\(limit)"),
            .init(name: "enableTotalRecordCount", value: "true"),
            .init(name: "addCurrentProgram", value: "true"),
            .init(name: "enableUserData", value: "true"),
            .init(name: "enableImages", value: "true"),
            .init(name: "imageTypeLimit", value: "1"),
            .init(name: "enableImageTypes", value: "Primary"),
            .init(name: "fields", value: "Overview,ChannelInfo"),
        ]
        if favoritesOnly { comps.queryItems?.append(.init(name: "isFavorite", value: "true")) }
        let page: LiveTVPage<ChannelResponse> = try await getLiveTV(comps, authHeader: authHeader)
        let channels = page.items.map { $0.toChannel() }
        return (channels, page.totalRecordCount ?? startIndex + channels.count)
    }

    /// Whether the server has any guide at all: an M3U playlist without an XMLTV or Schedules
    /// Direct listings provider has channels but no programmes.
    public func hasLiveTVGuide(credential: ServerCredential, authHeader: String) async -> Bool {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("LiveTv/Programs"))
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        let body: [String: Any] = [
            "UserId": credential.userID, "Limit": 1, "MinEndDate": JellyfinDate.string(.now),
            "EnableImages": false, "EnableUserData": false, "EnableTotalRecordCount": false,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let page: LiveTVPage<ProgramResponse> = try? await send(req) else { return true }
        return !page.items.isEmpty
    }

    /// GET /LiveTv/Channels/{id}, with what's on it now.
    public func getLiveTVChannel(credential: ServerCredential, authHeader: String, channelId: String) async throws -> LiveTVChannel {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveTv/Channels/\(channelId)"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "userId", value: credential.userID)]
        let channel: ChannelResponse = try await getLiveTV(comps, authHeader: authHeader)
        return channel.toChannel()
    }

    /// Channels and programmes whose name matches, best match first. The channel list only
    /// holds the pages loaded so far, so search asks the server. Programmes that have already
    /// ended are left out, the rest go soonest first.
    public func searchLiveTV(credential: ServerCredential, authHeader: String, query: String,
                             includePrograms: Bool = true, limit: Int = 30) async throws -> (channels: [LiveTVChannel], programs: [LiveTVProgram]) {
        func items(_ type: String) -> URLComponents {
            var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Items"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                .init(name: "userId", value: credential.userID),
                .init(name: "searchTerm", value: query),
                .init(name: "includeItemTypes", value: type),
                .init(name: "recursive", value: "true"),
                .init(name: "limit", value: "\(limit)"),
                .init(name: "fields", value: "ChannelInfo,Overview"),
                .init(name: "enableUserData", value: "true"),
                .init(name: "enableImageTypes", value: "Primary"),
                .init(name: "imageTypeLimit", value: "1"),
                .init(name: "enableTotalRecordCount", value: "false"),
            ]
            return comps
        }
        async let channelPage: LiveTVPage<ChannelResponse> = getLiveTV(items("TvChannel"), authHeader: authHeader)
        var programs: [LiveTVProgram] = []
        if includePrograms, let page: LiveTVPage<ProgramResponse> = try? await getLiveTV(items("LiveTvProgram"), authHeader: authHeader) {
            let now = Date()
            programs = page.items.compactMap { $0.toProgram() }.filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }
        }
        return (try await channelPage.items.map { $0.toChannel() }, programs)
    }

    func getLiveTVChannelCount(credential: ServerCredential, authHeader: String) async throws -> Int {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveTv/Channels"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "userId", value: credential.userID),
            .init(name: "limit", value: "0"),
            .init(name: "enableImages", value: "false"),
        ]
        let page: LiveTVPage<ChannelResponse> = try await getLiveTV(comps, authHeader: authHeader)
        return page.totalRecordCount ?? 0
    }

    /// POST /LiveTv/Programs: the guide for these channels between two times, by start time.
    public func getLiveTVPrograms(credential: ServerCredential, authHeader: String,
                                  channelIds: [String], from start: Date, to end: Date) async throws -> [LiveTVProgram] {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("LiveTv/Programs"))
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        let body: [String: Any] = [
            "UserId": credential.userID,
            "ChannelIds": channelIds,
            "MinEndDate": JellyfinDate.string(start),
            "MaxStartDate": JellyfinDate.string(end),
            "SortBy": ["StartDate"],
            "EnableImages": true,
            "ImageTypeLimit": 1,
            "EnableImageTypes": ["Primary"],
            "EnableUserData": false,
            "EnableTotalRecordCount": false,
            "Fields": ["Overview"],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let page: LiveTVPage<ProgramResponse> = try await send(req)
        return page.items.compactMap { $0.toProgram() }
    }

    /// GET /LiveTv/Programs/{id}, with its timers filled in.
    public func getLiveTVProgram(credential: ServerCredential, authHeader: String, programId: String) async throws -> LiveTVProgram? {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveTv/Programs/\(programId)"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "userId", value: credential.userID)]
        let program: ProgramResponse = try await getLiveTV(comps, authHeader: authHeader)
        return program.toProgram()
    }

    /// GET /LiveTv/Recordings, newest first.
    public func getLiveTVRecordings(credential: ServerCredential, authHeader: String) async throws -> [LiveTVRecording] {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveTv/Recordings"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "userId", value: credential.userID),
            .init(name: "enableUserData", value: "true"),
            .init(name: "enableImages", value: "true"),
            .init(name: "imageTypeLimit", value: "1"),
            .init(name: "enableImageTypes", value: "Primary,Thumb,Backdrop"),
            .init(name: "fields", value: "Overview,ChannelInfo"),
        ]
        let page: LiveTVPage<RecordingResponse> = try await getLiveTV(comps, authHeader: authHeader)
        return page.items.map { $0.toRecording() }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// GET /LiveTv/Timers: recordings that are scheduled or under way, soonest first.
    public func getLiveTVTimers(credential: ServerCredential, authHeader: String) async throws -> [LiveTVTimer] {
        let comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveTv/Timers"),
                                  resolvingAgainstBaseURL: false)!
        let page: LiveTVPage<TimerResponse> = try await getLiveTV(comps, authHeader: authHeader)
        return page.items.compactMap { $0.toTimer() }
            .filter { $0.status != "Cancelled" && $0.status != "Completed" }
            .sorted { $0.startDate < $1.startDate }
    }

    public func getLiveTVSeriesTimers(credential: ServerCredential, authHeader: String) async throws -> [LiveTVSeriesTimer] {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveTv/SeriesTimers"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "sortBy", value: "SortName"), .init(name: "sortOrder", value: "Ascending")]
        let page: LiveTVPage<SeriesTimerResponse> = try await getLiveTV(comps, authHeader: authHeader)
        return page.items.map { $0.toSeriesTimer() }
    }

    /// Records one showing, with the server's default padding.
    public func recordLiveTVProgram(credential: ServerCredential, authHeader: String, programId: String) async throws {
        let defaults = try await timerDefaults(credential: credential, authHeader: authHeader, programId: programId)
        try await postLiveTV("LiveTv/Timers", body: defaults, credential: credential, authHeader: authHeader)
    }

    /// Records every showing of the series the programme belongs to, with the server's defaults
    /// (new episodes on this channel, at any time).
    public func recordLiveTVSeries(credential: ServerCredential, authHeader: String, programId: String) async throws {
        let defaults = try await timerDefaults(credential: credential, authHeader: authHeader, programId: programId)
        try await postLiveTV("LiveTv/SeriesTimers", body: defaults, credential: credential, authHeader: authHeader)
    }

    public func cancelLiveTVTimer(credential: ServerCredential, authHeader: String, timerId: String) async throws {
        try await deleteLiveTV("LiveTv/Timers/\(timerId)", credential: credential, authHeader: authHeader)
    }

    public func cancelLiveTVSeriesTimer(credential: ServerCredential, authHeader: String, seriesTimerId: String) async throws {
        try await deleteLiveTV("LiveTv/SeriesTimers/\(seriesTimerId)", credential: credential, authHeader: authHeader)
    }

    /// POST /LiveStreams/Close. A tuner stays busy until its stream is closed or times out.
    public func closeLiveStream(credential: ServerCredential, authHeader: String, liveStreamId: String) async {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveStreams/Close"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "liveStreamId", value: liveStreamId)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        _ = try? await URLSession.arcfin.data(for: req)
    }

    // MARK: Helpers

    /// GET /LiveTv/Timers/Defaults: the server's ready-made timer for a programme, sent back as is.
    private func timerDefaults(credential: ServerCredential, authHeader: String, programId: String) async throws -> Data {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("LiveTv/Timers/Defaults"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "programId", value: programId)]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func getLiveTV<T: Decodable>(_ comps: URLComponents, authHeader: String) async throws -> T {
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        return try await send(req)
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postLiveTV(_ path: String, body: Data, credential: ServerCredential, authHeader: String) async throws {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = body
        let (_, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func deleteLiveTV(_ path: String, credential: ServerCredential, authHeader: String) async throws {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (_, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Responses

private struct LiveTVPage<Item: Decodable>: Decodable {
    let items: [Item]
    let totalRecordCount: Int?
    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount" }
}

private struct ChannelResponse: Decodable {
    let id: String
    let name: String?
    let number: String?
    let imageTags: [String: String]?
    let userData: UserDataResponse?
    let currentProgram: ProgramResponse?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", number = "ChannelNumber", imageTags = "ImageTags"
        case userData = "UserData", currentProgram = "CurrentProgram"
    }

    func toChannel() -> LiveTVChannel {
        LiveTVChannel(id: id, name: name ?? number ?? "", number: number, primaryImageTag: imageTags?["Primary"],
                      isFavorite: userData?.isFavorite ?? false, currentProgram: currentProgram?.toProgram())
    }
}

private struct ProgramResponse: Decodable {
    let id: String
    let channelId: String?
    let channelName: String?
    let name: String?
    let episodeTitle: String?
    let overview: String?
    let startDate: String?
    let endDate: String?
    let isSeries: Bool?
    let isMovie: Bool?
    let isNews: Bool?
    let isKids: Bool?
    let isSports: Bool?
    let isLive: Bool?
    let isPremiere: Bool?
    let isNew: Bool?
    let officialRating: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let timerId: String?
    let seriesTimerId: String?
    let imageTags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", channelId = "ChannelId", channelName = "ChannelName", name = "Name"
        case episodeTitle = "EpisodeTitle", overview = "Overview"
        case startDate = "StartDate", endDate = "EndDate"
        case isSeries = "IsSeries", isMovie = "IsMovie", isNews = "IsNews", isKids = "IsKids"
        case isSports = "IsSports", isLive = "IsLive", isPremiere = "IsPremiere", isNew = "IsNew"
        case officialRating = "OfficialRating", parentIndexNumber = "ParentIndexNumber", indexNumber = "IndexNumber"
        case timerId = "TimerId", seriesTimerId = "SeriesTimerId", imageTags = "ImageTags"
    }

    func toProgram() -> LiveTVProgram? {
        guard let channelId, let start = startDate.flatMap(JellyfinDate.parse),
              let end = endDate.flatMap(JellyfinDate.parse) else { return nil }
        return LiveTVProgram(
            id: id, channelId: channelId, channelName: channelName, name: name ?? "",
            episodeTitle: episodeTitle, overview: overview, startDate: start, endDate: end,
            isSeries: isSeries ?? false, isMovie: isMovie ?? false, isNews: isNews ?? false,
            isKids: isKids ?? false, isSports: isSports ?? false, isLive: isLive ?? false,
            isPremiere: isPremiere ?? false, isNew: isNew ?? false, officialRating: officialRating,
            seasonNumber: parentIndexNumber, episodeNumber: indexNumber,
            timerId: timerId.flatMap { $0.isEmpty ? nil : $0 },
            seriesTimerId: seriesTimerId.flatMap { $0.isEmpty ? nil : $0 },
            primaryImageTag: imageTags?["Primary"])
    }
}

private struct RecordingResponse: Decodable {
    let item: JellyfinItemResponse
    let channelName: String?
    let startDate: String?
    let status: String?

    enum CodingKeys: String, CodingKey { case channelName = "ChannelName", startDate = "StartDate", status = "Status" }

    init(from decoder: Decoder) throws {
        item = try JellyfinItemResponse(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelName = try c.decodeIfPresent(String.self, forKey: .channelName)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    func toRecording() -> LiveTVRecording {
        LiveTVRecording(item: item.toMediaItem(), channelName: channelName,
                        startDate: startDate.flatMap(JellyfinDate.parse), isRecording: status == "InProgress")
    }
}

private struct TimerResponse: Decodable {
    let id: String?
    let programId: String?
    let channelId: String?
    let channelName: String?
    let name: String?
    let startDate: String?
    let endDate: String?
    let status: String?
    let seriesTimerId: String?
    let programInfo: ProgramResponse?

    enum CodingKeys: String, CodingKey {
        case id = "Id", programId = "ProgramId", channelId = "ChannelId", channelName = "ChannelName", name = "Name"
        case startDate = "StartDate", endDate = "EndDate", status = "Status", seriesTimerId = "SeriesTimerId"
        case programInfo = "ProgramInfo"
    }

    func toTimer() -> LiveTVTimer? {
        guard let id, let start = startDate.flatMap(JellyfinDate.parse), let end = endDate.flatMap(JellyfinDate.parse)
        else { return nil }
        return LiveTVTimer(id: id, programId: programId, channelId: channelId, channelName: channelName,
                           name: name ?? programInfo?.name ?? "", startDate: start, endDate: end,
                           status: status ?? "New", seriesTimerId: seriesTimerId.flatMap { $0.isEmpty ? nil : $0 },
                           episodeTitle: programInfo?.episodeTitle)
    }
}

private struct SeriesTimerResponse: Decodable {
    let id: String
    let name: String?
    let channelName: String?
    let recordAnyChannel: Bool?
    let recordAnyTime: Bool?
    let recordNewOnly: Bool?
    let parentPrimaryImageItemId: String?
    let parentPrimaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", channelName = "ChannelName", recordAnyChannel = "RecordAnyChannel"
        case recordAnyTime = "RecordAnyTime", recordNewOnly = "RecordNewOnly"
        case parentPrimaryImageItemId = "ParentPrimaryImageItemId", parentPrimaryImageTag = "ParentPrimaryImageTag"
    }

    func toSeriesTimer() -> LiveTVSeriesTimer {
        LiveTVSeriesTimer(id: id, name: name ?? "", channelName: channelName,
                          recordAnyChannel: recordAnyChannel ?? false, recordAnyTime: recordAnyTime ?? false,
                          recordNewOnly: recordNewOnly ?? false, imageItemId: parentPrimaryImageItemId,
                          imageTag: parentPrimaryImageTag)
    }
}
