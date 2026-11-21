// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
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

@Suite("Downloads per profile")
struct DownloadProfileTests {
    private let adult = DownloadProfile(id: "A", userId: "user-a", serverBaseURL: "https://media.example")
    private let child = DownloadProfile(id: "B", userId: "user-b", serverBaseURL: "https://media.example")

    private func item(_ itemId: String, profile: DownloadProfile, folderName: String? = nil) -> DownloadedItem {
        let item = DownloadedItem(itemId: itemId, name: itemId, typeRaw: "Movie", serverId: profile.id,
                                  serverBaseURL: profile.serverBaseURL, userId: profile.userId, videoFileName: "video.mp4")
        item.folderName = folderName
        return item
    }

    @Test("A profile owns only its own downloads")
    func ownership() {
        let download = item("X", profile: adult)
        #expect(download.belongs(to: adult))
        #expect(!download.belongs(to: child))
        #expect(!download.belongs(to: nil))
    }

    @Test("Signed in again as the same user on the same server, the downloads are still theirs")
    func signedInAgain() {
        let again = DownloadProfile(id: "A2", userId: "user-a", serverBaseURL: "https://media.example")
        let elsewhere = DownloadProfile(id: "A3", userId: "user-a", serverBaseURL: "https://other.example")
        #expect(item("X", profile: adult).belongs(to: again))
        #expect(!item("X", profile: adult).belongs(to: elsewhere))
    }

    @Test("Two profiles can store the same title on one store")
    func sameTitleTwice() throws {
        let context = ModelContext(try Persistence.makeContainer(inMemory: true))
        context.insert(item("X", profile: adult))
        context.insert(item("X", profile: child, folderName: "Profiles/B/X"))
        try context.save()
        let rows = try context.fetch(FetchDescriptor<DownloadedItem>())
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.userId)) == ["user-a", "user-b"])
    }

    @Test("A title's folder is its own unless another profile's copy is in it")
    func folders() {
        #expect(DownloadStore.folderName(for: "X", profileId: "B", itemFolderTaken: false) == "X")
        #expect(DownloadStore.folderName(for: "X", profileId: "B", itemFolderTaken: true) == "Profiles/B/X")
        #expect(item("X", profile: adult).storedFolderName == "X")
        #expect(item("X", profile: child, folderName: "Profiles/B/X").storedFolderName == "Profiles/B/X")
        let dir = DownloadStore.directory(forFolder: "Profiles/B/X")
        #expect(DownloadStore.folderName(of: dir) == "Profiles/B/X")
        #expect(DownloadStore.folderName(of: DownloadStore.directory(for: "X")) == "X")
        #expect(DownloadStore.folderName(of: URL(fileURLWithPath: "/old/Downloads/Profiles/B/X")) == "Profiles/B/X")
        #expect(DownloadStore.folderName(of: URL(fileURLWithPath: "/old/Downloads/X")) == "X")
    }

    @Test("Leftover folders are the ones nothing keeps, in either place")
    func leftovers() {
        let present = ["X", "Y", "S", "Profiles/B/X", "Profiles/B/Z", "Profiles/C/W"]
        let leftover = DownloadStore.leftoverFolders(present: present, keeping: ["X", "S", "Profiles/B/X"], underway: ["W"])
        #expect(leftover == ["Y", "Profiles/B/Z"])
    }

    @Test("Keys for removal after watching name one profile's copy; older bare ids name the old one")
    func profileKeys() {
        let old = item("X", profile: adult)
        let new = item("X", profile: child, folderName: "Profiles/B/X")
        let moved = item("X", profile: adult, folderName: "X")
        #expect(old.matches(profileKey: old.profileKey))
        #expect(!new.matches(profileKey: old.profileKey))
        #expect(old.matches(profileKey: "X"))
        #expect(!new.matches(profileKey: "X"))
        #expect(!moved.matches(profileKey: "X"))
    }
}
