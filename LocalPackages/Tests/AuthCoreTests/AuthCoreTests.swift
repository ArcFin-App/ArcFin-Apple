import Testing
@testable import AuthCore

@Suite("ServerCredential")
struct AuthCoreTests {

    @Test("ServerCredential is equatable by id")
    func credentialEquality() throws {
        let url = try #require(URL(string: "https://jellyfin.example.com"))
        let cred = ServerCredential(baseURL: url, userID: "u1", accessToken: "tok", displayName: "Home")
        #expect(cred == cred)
    }

    @Test("AuthState unauthenticated by default")
    func defaultAuthState() {
        let state = AuthState.unauthenticated
        #expect(state == .unauthenticated)
    }
}
