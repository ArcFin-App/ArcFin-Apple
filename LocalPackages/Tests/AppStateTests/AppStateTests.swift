import Testing
import ComposableArchitecture
@testable import AppState

@Suite("RootReducer")
struct AppStateTests {

    @Test("Initial state is unauthenticated")
    func initialStateIsUnauthenticated() {
        let state = RootReducer.State()
        #expect(state.authState == .unauthenticated)
    }

    @Test("Default tab is home")
    func defaultTabIsHome() {
        let state = RootReducer.State()
        #expect(state.selectedTab == .home)
    }
}
