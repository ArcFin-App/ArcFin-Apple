import Testing
@testable import SearchKit

@Suite("SearchResults")
struct SearchKitTests {

    @Test("Empty results by default")
    func emptyResultsByDefault() {
        let results = SearchResults()
        #expect(results.serverResults.isEmpty)
#if !os(tvOS)
        #expect(results.spotlightResults.isEmpty)
#endif
    }
}
