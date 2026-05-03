import Testing
import SwiftData
@testable import Persistence

@Suite("Persistence container")
struct PersistenceTests {

    @Test("In-memory container creation succeeds")
    func inMemoryContainerCreates() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        #expect(container.schema != nil)
    }
}
