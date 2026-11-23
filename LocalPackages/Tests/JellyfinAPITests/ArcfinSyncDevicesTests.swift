// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Arcfin Sync v2 responses")
struct ArcfinSyncDevicesTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test("A plugin from before v2 still reads as installed, at API version 1")
    func oldStatus() throws {
        let status = try decode(ArcfinSyncStatus.self, #"{"Installed":true,"Version":"0.3.1.0"}"#)
        #expect(status.installed)
        #expect(status.apiVersion == 1)
        #expect(!status.hasDevicesAndPolicy)
    }

    @Test("A v2 plugin says so")
    func newStatus() throws {
        let status = try decode(ArcfinSyncStatus.self,
                                #"{"Installed":true,"Version":"0.4.0.0","ApiVersion":2,"Features":["schema","devices"]}"#)
        #expect(status.hasDevicesAndPolicy)
        #expect(status.features == ["schema", "devices"])
    }

    @Test("Sync state reads .NET dates with or without a time zone")
    func syncState() throws {
        let state = try decode(ArcfinSyncState.self, """
        {"Settings":[{"Key":"skipIntro","Value":"true","IsLocked":false,"Source":"user"},
                     {"Key":"videoQuality","Value":null,"IsLocked":true,"Source":"locked"}],
         "UpdatedAt":"2026-11-23T10:15:30.1234567","UpdatedByDeviceId":"abc","UpdatedByDeviceName":"TV"}
        """)
        #expect(state.values == ["skipIntro": "true"])
        #expect(state.lockedKeys == ["videoQuality"])
        #expect(state.updatedAt == JellyfinDate.parse("2026-11-23T10:15:30.123Z"))
        #expect(state.updatedByDeviceId == "abc")
    }

    @Test("A device with null settings and no last-seen time still decodes")
    func device() throws {
        let device = try decode(ArcfinSyncDevice.self, """
        {"DeviceId":"d1","Name":"Den","CustomName":null,"JellyfinDeviceName":"Apple TV","Platform":"tvOS",
         "SyncMode":"ask","IsCurrent":true,"Settings":{"skipIntro":"true","skipCredits":null}}
        """)
        #expect(device.name == "Den")
        #expect(device.settings == ["skipIntro": "true"])
        #expect(device.lastSeen == nil)
        #expect(device.isCurrent)
    }

    @Test("Device ids in a path can't add path segments")
    func pathComponent() {
        #expect(ArcfinSyncClient.component("a/../b") == "a%2F..%2Fb")
    }
}
