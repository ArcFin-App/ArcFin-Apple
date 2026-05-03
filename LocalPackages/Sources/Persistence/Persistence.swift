import SwiftData
import Telemetry

// MARK: - Container factory

public enum Persistence: Sendable {

    private static let log = Telemetry.logger(category: "Persistence")

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(currentModels)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // Register new SwiftData models here as they are created.
    static var currentModels: [any PersistentModel.Type] {
        []
    }
}
