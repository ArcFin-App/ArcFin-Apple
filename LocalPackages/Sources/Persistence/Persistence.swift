// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
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

    /// A store that can't be opened after an update is set aside, not crashed on at every
    /// launch: the app starts with an empty one, and the old files stay beside it.
    public static func makeContainerRecoveringFromFailure() -> ModelContainer {
        do {
            return try makeContainer()
        } catch {
            log.error("Store failed to open, setting it aside: \(error.localizedDescription, privacy: .public)")
        }
        let store = ModelConfiguration(schema: Schema(currentModels)).url
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-shm", "-wal"] {
            let file = URL(fileURLWithPath: store.path + suffix)
            try? FileManager.default.moveItem(at: file, to: URL(fileURLWithPath: file.path + ".unreadable-\(stamp)"))
        }
        if let container = try? makeContainer() { return container }
        do {
            return try makeContainer(inMemory: true)
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }

    // Register new SwiftData models here as they are created.
    static var currentModels: [any PersistentModel.Type] {
        [DownloadedItem.self, DownloadedSeries.self]
    }
}
