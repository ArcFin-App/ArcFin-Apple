// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import CoreData
import SwiftData
import Telemetry
import os

// MARK: - Container factory

public enum Persistence: Sendable {

    private static let log = Telemetry.logger(category: "Persistence")

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(currentModels)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(currentModels)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    }

    static var defaultStoreURL: URL { ModelConfiguration(schema: Schema(currentModels)).url }

    /// A store this build's models can't be opened against is set aside, not crashed on at every
    /// launch: the app starts with an empty one, and the old files stay beside it until a later
    /// launch can open them again. Any other failure (a full disk, a locked device) leaves the
    /// store where it is for this launch and tries it again on the next.
    public static func makeContainerRecoveringFromFailure() -> ModelContainer {
        makeContainerRecoveringFromFailure(at: defaultStoreURL)
    }

    static func makeContainerRecoveringFromFailure(at store: URL) -> ModelContainer {
        restoreSetAsideStore(at: store)
        do {
            return try makeContainer(at: store)
        } catch {
            let failure = OpenFailure(error)
            log.error("Store failed to open (\(String(describing: failure), privacy: .public)): \(error.localizedDescription, privacy: .public)")
            if failure == .incompatible {
                setAside(store)
                if let container = try? makeContainer(at: store) { return container }
            }
        }
        do {
            return try makeContainer(inMemory: true)
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }

    /// A store set aside by makeContainerRecoveringFromFailure is still beside the new one: the
    /// downloads it listed are on disk with no record here, and shouldn't be cleared as unknown.
    public static func hasSetAsideStore() -> Bool {
        hasSetAsideStore(at: defaultStoreURL)
    }

    static func hasSetAsideStore(at store: URL) -> Bool {
        !setAsideStamps(of: store).isEmpty
    }

    // Register new SwiftData models here as they are created.
    static var currentModels: [any PersistentModel.Type] {
        [DownloadedItem.self, DownloadedSeries.self]
    }

    // MARK: - Setting a store aside and back

    private static let storeSuffixes = ["", "-shm", "-wal"]
    private static let setAsideMarker = ".unreadable-"

    private static func file(_ store: URL, _ suffix: String, stamp: String? = nil) -> URL {
        URL(fileURLWithPath: store.path + suffix + (stamp.map { setAsideMarker + $0 } ?? ""))
    }

    private static func setAside(_ store: URL) {
        let stamp = String(Int(Date().timeIntervalSince1970))
        for suffix in storeSuffixes {
            try? FileManager.default.moveItem(at: file(store, suffix), to: file(store, suffix, stamp: stamp))
        }
    }

    private static func setAsideStamps(of store: URL) -> [String] {
        let prefix = store.lastPathComponent + setAsideMarker
        let names = (try? FileManager.default.contentsOfDirectory(atPath: store.deletingLastPathComponent().path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// While the store in use holds nothing, a set-aside one that now opens (a later build reads
    /// it, or what kept it from opening has gone) goes back in its place. It's tried on a copy
    /// first, and the set-aside files are only removed once it has opened where it belongs.
    private static func restoreSetAsideStore(at store: URL) {
        let stamps = setAsideStamps(of: store)
        guard !stamps.isEmpty, (rowCount(at: store) ?? 1) == 0 else { return }
        let trial = store.deletingLastPathComponent().appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: trial) }
        // Repeated set-asides can leave empty stores behind the one with downloads in it.
        var best: (stamp: String, rows: Int)?
        var empty: [String] = []
        for stamp in stamps {
            let copy = trial.appendingPathComponent(stamp, isDirectory: true).appendingPathComponent(store.lastPathComponent)
            guard copySetAside(store, stamp: stamp, to: copy), let rows = rowCount(at: copy) else { continue }
            if rows == 0 { empty.append(stamp) } else if rows > best?.rows ?? 0 { best = (stamp, rows) }
        }
        guard let best else { return }
        let replaced = trial.appendingPathComponent("replaced", isDirectory: true)
        try? FileManager.default.createDirectory(at: replaced, withIntermediateDirectories: true)
        for suffix in storeSuffixes {
            try? FileManager.default.moveItem(at: file(store, suffix), to: replaced.appendingPathComponent(store.lastPathComponent + suffix))
        }
        guard copySetAside(store, stamp: best.stamp, to: store), (rowCount(at: store) ?? 0) > 0 else {
            for suffix in storeSuffixes {
                try? FileManager.default.removeItem(at: file(store, suffix))
                try? FileManager.default.moveItem(at: replaced.appendingPathComponent(store.lastPathComponent + suffix), to: file(store, suffix))
            }
            return
        }
        log.notice("Restored a store that had been set aside")
        // One that still won't open, or has other downloads, stays for a later build to read.
        for stamp in [best.stamp] + empty {
            for suffix in storeSuffixes { try? FileManager.default.removeItem(at: file(store, suffix, stamp: stamp)) }
        }
    }

    private static func copySetAside(_ store: URL, stamp: String, to destination: URL) -> Bool {
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in storeSuffixes {
            let source = file(store, suffix, stamp: stamp)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            do {
                try FileManager.default.copyItem(at: source, to: file(destination, suffix))
            } catch {
                return false
            }
        }
        return FileManager.default.fileExists(atPath: destination.path)
    }

    /// Downloads and series in the store at `url`, 0 when there's no store yet, nil when it
    /// won't open. The container is gone again once this returns.
    private static func rowCount(at url: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        return autoreleasepool {
            guard let container = try? makeContainer(at: url) else { return nil }
            let context = ModelContext(container)
            guard let items = try? context.fetchCount(FetchDescriptor<DownloadedItem>()),
                  let series = try? context.fetchCount(FetchDescriptor<DownloadedSeries>())
            else { return nil }
            return items + series
        }
    }
}

// MARK: - Why a store didn't open

/// Only a store this build's models can't read (or that isn't a store at all) is set aside. A
/// full disk, a device still locked, or anything not recognised is left alone and tried again.
enum OpenFailure: Equatable, CustomStringConvertible {
    case incompatible
    case transient

    init(_ error: Error) {
        let chain = Self.errorChain(error)
        if chain.contains(where: Self.isTransient) {
            self = .transient
        } else if chain.contains(where: Self.isIncompatible) {
            self = .incompatible
        } else {
            self = .transient
        }
    }

    var description: String {
        switch self {
        case .incompatible: "incompatible"
        case .transient: "transient"
        }
    }

    private static let sqliteDomain = "NSSQLiteErrorDomain"
    // Model, migration and mapping errors (NSPersistentStoreIncompatibleSchemaError,
    // NSPersistentStoreIncompatibleVersionHashError, NSMigration…Error, NSInferredMappingModelError).
    private static let incompatibleCocoaCodes: Set<Int> = [134020, 134100, 134110, 134111, 134130, 134140, 134150, 134160, 134170, 134190]
    // File can't be read as a store; SQLITE_CORRUPT, SQLITE_NOTADB.
    private static let corruptCocoaCodes: Set<Int> = [259]
    private static let corruptSQLiteCodes: Set<Int> = [11, 26]
    // Permission, out of space, volume read-only, unknown read/write failures.
    private static let transientCocoaCodes: Set<Int> = [256, 257, 512, 513, 640, 642, 134120]
    // SQLITE_PERM, BUSY, LOCKED, NOMEM, READONLY, IOERR, FULL, CANTOPEN, AUTH.
    private static let transientSQLiteCodes: Set<Int> = [3, 5, 6, 7, 8, 10, 13, 14, 23]

    private static func sqliteCode(_ error: NSError) -> Int? {
        if error.domain == sqliteDomain { return error.code }
        return (error.userInfo[sqliteDomain] as? NSNumber)?.intValue
    }

    private static func isTransient(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain { return true }
        if error.domain == NSCocoaErrorDomain, transientCocoaCodes.contains(error.code) { return true }
        return sqliteCode(error).map(transientSQLiteCodes.contains) ?? false
    }

    private static func isIncompatible(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           incompatibleCocoaCodes.contains(error.code) || corruptCocoaCodes.contains(error.code) { return true }
        return sqliteCode(error).map(corruptSQLiteCodes.contains) ?? false
    }

    /// The error and everything under it. SwiftData's own error keeps the Core Data one in a
    /// stored property rather than in userInfo, so that's read by reflection.
    static func errorChain(_ error: Error) -> [NSError] {
        var found: [NSError] = []
        var pending: [Error] = [error]
        while let next = pending.popLast(), found.count < 32 {
            let ns = next as NSError
            found.append(ns)
            pending.append(contentsOf: ns.underlyingErrors)
            if let detailed = ns.userInfo[NSDetailedErrorsKey] as? [Error] { pending.append(contentsOf: detailed) }
            for child in Mirror(reflecting: next).children {
                if let nested = child.value as? Error { pending.append(nested) }
            }
        }
        return found
    }
}
