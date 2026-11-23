// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import Arcfin

struct DownloadRangeRetryTests {
    @Test func aDroppedConnectionIsTriedAgainUpToThreeTimes() {
        let dropped = URLError(.networkConnectionLost)
        #expect(DownloadManager.retriesPart(after: dropped, attempt: 1))
        #expect(DownloadManager.retriesPart(after: dropped, attempt: 2))
        #expect(!DownloadManager.retriesPart(after: dropped, attempt: 3))
        #expect(DownloadManager.retriesPart(after: URLError(.timedOut), attempt: 1))
    }

    @Test func aCancelARefusalOrAnErrorPageIsNotTriedAgain() {
        #expect(!DownloadManager.retriesPart(after: URLError(.cancelled), attempt: 1))
        #expect(!DownloadManager.retriesPart(after: CancellationError(), attempt: 1))
        #expect(!DownloadManager.retriesPart(after: URLError(.badServerResponse), attempt: 1))
        #expect(!DownloadManager.retriesPart(after: DownloadError.permissionDenied, attempt: 1))
        #expect(!DownloadManager.retriesPart(after: CocoaError(.fileWriteOutOfSpace), attempt: 1))
    }
}
