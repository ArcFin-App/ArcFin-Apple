// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import SwiftData
@testable import Persistence

/// The 0.4.0 models, as that build wrote the store.
enum Store040 {
    @Model
    final class DownloadedItem {
        @Attribute(.unique) var itemId: String
        var name: String
        var typeRaw: String
        var overview: String?
        var runtimeTicks: Int64
        var productionYear: Int?
        var communityRating: Double?
        var officialRating: String?
        var genres: [String]
        var seriesId: String?
        var seriesName: String?
        var seasonNumber: Int?
        var episodeNumber: Int?
        var serverId: String
        var serverBaseURL: String
        var userId: String
        var videoFileName: String
        var posterFileName: String?
        var backdropFileName: String?
        var subtitleFileNames: [String]
        var subtitleLanguages: [String]
        var trickplayFileNames: [String]
        var trickplayWidth: Int?
        var trickplayHeight: Int?
        var trickplayTileWidth: Int?
        var trickplayTileHeight: Int?
        var trickplayIntervalMs: Int?
        var trickplayThumbnailCount: Int?
        var introEndSeconds: Double?
        var creditsStartSeconds: Double?
        var introStartSeconds: Double?
        var creditsEndSeconds: Double?
        var recapStartSeconds: Double?
        var recapEndSeconds: Double?
        var previewStartSeconds: Double?
        var previewEndSeconds: Double?
        var skipSegmentsSaved: Bool = false
        var fileSizeBytes: Int64
        var downloadedAt: Date
        var playbackPositionTicks: Int64
        var played: Bool
        var needsSync: Bool = false
        var progressChangedAt: Date?
        var tagline: String?
        var studios: [String] = []
        var directors: [String] = []
        var castNames: [String] = []
        var castRoles: [String] = []
        var castPhotoFileNames: [String] = []
        var videoSummary: String?
        var audioSummary: String?

        init(itemId: String, name: String, userId: String) {
            self.itemId = itemId; self.name = name; self.typeRaw = "Movie"
            self.runtimeTicks = 0; self.genres = ["Drama"]
            self.serverId = "profile-a"; self.serverBaseURL = "https://media.example"; self.userId = userId
            self.videoFileName = "video.mp4"; self.subtitleFileNames = []; self.subtitleLanguages = []
            self.trickplayFileNames = []; self.fileSizeBytes = 1_000; self.downloadedAt = Date(timeIntervalSince1970: 1_700_000_000)
            self.playbackPositionTicks = 42; self.played = false; self.needsSync = true
        }
    }

    @Model
    final class DownloadedSeries {
        @Attribute(.unique) var seriesId: String
        var name: String
        var overview: String?
        var genres: [String]
        var communityRating: Double?
        var officialRating: String?
        var productionYear: Int?
        var posterFileName: String?
        var backdropFileName: String?

        init(seriesId: String, name: String) {
            self.seriesId = seriesId; self.name = name; self.genres = []
        }
    }
}

/// A model no build has shipped, to stand in for one this build can't migrate from.
enum StoreUnreadable {
    @Model
    final class DownloadedItem {
        var itemId: Int
        var name: Date
        init() { itemId = 1; name = Date() }
    }
}

@Suite("Opening a store from an older build", .serialized)
struct StoreUpgradeTests {
    private func storeURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arcfin-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("default.store")
    }

    private func writeOldStore(at url: URL, items: [String] = ["movie-1", "movie-2"]) throws {
        let schema = Schema([Store040.DownloadedItem.self, Store040.DownloadedSeries.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        for id in items { context.insert(Store040.DownloadedItem(itemId: id, name: id, userId: "user-a")) }
        if !items.isEmpty { context.insert(Store040.DownloadedSeries(seriesId: "series-1", name: "A Series")) }
        try context.save()
    }

    private func writeUnreadableStore(at url: URL) throws {
        let schema = Schema([StoreUnreadable.DownloadedItem.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        context.insert(StoreUnreadable.DownloadedItem())
        try context.save()
    }

    private func setAside(_ url: URL, stamp: String) throws {
        for suffix in ["", "-shm", "-wal"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            try FileManager.default.moveItem(atPath: url.path + suffix, toPath: url.path + suffix + ".unreadable-" + stamp)
        }
    }

    private func itemIds(_ container: ModelContainer) throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<DownloadedItem>(sortBy: [SortDescriptor(\.itemId)])).map(\.itemId)
    }

    private func isOnDisk(_ container: ModelContainer) -> Bool {
        !container.configurations.contains(where: \.isStoredInMemoryOnly)
    }

    @Test("A 0.4.0 store opens with its downloads, and two profiles can then keep the same title")
    func opensOldStore() throws {
        let url = try storeURL()
        try writeOldStore(at: url)
        let container = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(isOnDisk(container))
        #expect(!Persistence.hasSetAsideStore(at: url))
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<DownloadedItem>(sortBy: [SortDescriptor(\.itemId)]))
        #expect(items.map(\.itemId) == ["movie-1", "movie-2"])
        #expect(items.first?.playbackPositionTicks == 42)
        #expect(items.first?.needsSync == true)
        #expect(items.first?.genres == ["Drama"])
        #expect(items.first?.folderName == nil)
        #expect(items.first?.commercialSpans == nil)
        #expect(items.first?.playCountAtDownload == nil)
        #expect(items.first?.serverPlayCount == nil)
        #expect(try context.fetch(FetchDescriptor<DownloadedSeries>()).map(\.seriesId) == ["series-1"])
        let copy = DownloadedItem(itemId: "movie-1", name: "First", typeRaw: "Movie", serverId: "profile-b",
                                  serverBaseURL: "https://media.example", userId: "user-b", videoFileName: "video.mp4")
        copy.folderName = "Profiles/profile-b/movie-1"
        context.insert(copy)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<DownloadedItem>()) == 3)
    }

    @Test("A store from before the versioned schema opens as version 1 with its downloads")
    func opensUnversionedStore() throws {
        let url = try storeURL()
        let schema = Schema([DownloadedItem.self, DownloadedSeries.self])
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(container)
            context.insert(DownloadedItem(itemId: "movie-1", name: "First", typeRaw: "Movie", serverId: "profile-a",
                                          serverBaseURL: "https://media.example", userId: "user-a", videoFileName: "video.mp4"))
            context.insert(DownloadedSeries(seriesId: "series-1", name: "A Series"))
            try context.save()
        }
        let container = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(isOnDisk(container))
        #expect(!Persistence.hasSetAsideStore(at: url))
        #expect(try itemIds(container) == ["movie-1"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<DownloadedSeries>()).map(\.seriesId) == ["series-1"])
    }

    @Test("A store from a model this build can't read is set aside, and the app gets a fresh one on disk")
    func setsAsideIncompatible() throws {
        let url = try storeURL()
        try writeUnreadableStore(at: url)
        do {
            _ = try Persistence.makeContainer(at: url)
            Issue.record("An unreadable model opened")
        } catch {
            #expect(OpenFailure(error) == .incompatible)
        }
        let container = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(isOnDisk(container))
        #expect(Persistence.hasSetAsideStore(at: url))
        #expect(try itemIds(container).isEmpty)
    }

    @Test("A store that can't be read for now is left where it is, and this launch runs in memory")
    func leavesUnreachableStore() throws {
        let url = try storeURL()
        try writeOldStore(at: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        do {
            _ = try Persistence.makeContainer(at: url)
            Issue.record("A store without read access opened")
        } catch {
            #expect(OpenFailure(error) == .transient)
        }
        let container = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(!isOnDisk(container))
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!Persistence.hasSetAsideStore(at: url))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try itemIds(Persistence.makeContainerRecoveringFromFailure(at: url)) == ["movie-1", "movie-2"])
    }

    @Test("An unrecognised failure is never a reason to set a store aside")
    func unknownIsTransient() {
        struct Unexpected: Error {}
        #expect(OpenFailure(Unexpected()) == .transient)
        let migrationWrappingFullDisk = NSError(domain: NSCocoaErrorDomain, code: 134110, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSCocoaErrorDomain, code: 640),
        ])
        #expect(OpenFailure(migrationWrappingFullDisk) == .transient)
        #expect(OpenFailure(NSError(domain: NSCocoaErrorDomain, code: 134140)) == .incompatible)
    }

    @Test("A set-aside store that opens again goes back in place while the new one is empty")
    func restoresSetAside() throws {
        let url = try storeURL()
        try writeOldStore(at: url)
        try setAside(url, stamp: "100")
        // A later empty set-aside, as repeated failures could leave, doesn't win over the one with downloads.
        try writeOldStore(at: url, items: [])
        try setAside(url, stamp: "200")
        try writeOldStore(at: url, items: [])
        let container = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(isOnDisk(container))
        #expect(try itemIds(container) == ["movie-1", "movie-2"])
        #expect(!Persistence.hasSetAsideStore(at: url))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(!leftovers.contains { $0.hasPrefix("restore-") })
    }

    @Test("A set-aside store stays aside once the new store has downloads of its own")
    func keepsNewStoreWithDownloads() throws {
        let url = try storeURL()
        try writeOldStore(at: url, items: ["old"])
        try setAside(url, stamp: "100")
        try writeOldStore(at: url, items: ["new"])
        let container = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(try itemIds(container) == ["new"])
        #expect(Persistence.hasSetAsideStore(at: url))
    }

    @Test("Restoring one set-aside store keeps another that still won't open")
    func keepsUnreadableBesideRestored() throws {
        let url = try storeURL()
        try writeUnreadableStore(at: url)
        try setAside(url, stamp: "100")
        try writeOldStore(at: url)
        try setAside(url, stamp: "200")
        try writeOldStore(at: url, items: [])
        let container = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(try itemIds(container) == ["movie-1", "movie-2"])
        #expect(FileManager.default.fileExists(atPath: url.path + ".unreadable-100"))
        #expect(!FileManager.default.fileExists(atPath: url.path + ".unreadable-200"))
        #expect(Persistence.hasSetAsideStore(at: url))
    }

    @Test("A set-aside store that still won't open stays aside")
    func keepsUnreadableSetAside() throws {
        let url = try storeURL()
        try writeUnreadableStore(at: url)
        _ = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(Persistence.hasSetAsideStore(at: url))
        let container = Persistence.makeContainerRecoveringFromFailure(at: url)
        #expect(isOnDisk(container))
        #expect(Persistence.hasSetAsideStore(at: url))
    }
}
