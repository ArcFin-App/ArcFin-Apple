import SwiftUI
import SwiftData
import Persistence

@main
struct ArcfinApp: App {

    var sharedModelContainer: ModelContainer = {
        do {
            return try Persistence.makeContainer()
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
