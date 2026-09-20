import SwiftUI
import SwiftData
import Persistence

@main
struct ArcfinApp: App {
    #if canImport(UIKit) && !os(tvOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

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
        #if os(macOS)
        // MainTabView's .tabViewStyle(.sidebarAdaptable) already renders as a real macOS
        // sidebar — no separate NavigationSplitView shell needed. This just gives the
        // window itself sane native sizing instead of whatever SwiftUI's bare default is.
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
        }
        #endif
    }
}
