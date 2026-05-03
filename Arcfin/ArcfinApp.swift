import SwiftUI
import SwiftData

@main
struct ArcfinApp: App {

    var sharedModelContainer: ModelContainer = {
        // Models registered via Persistence package — empty schema until first model added.
        let schema = Schema([])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
