// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import ImageCache

struct ImageRetryTests {
    @Test func aMissingImageIsNotTriedAgain() {
        #expect(ImageCache.retry(statusCode: 404, isConnectivityError: false) == .giveUp)
        #expect(ImageCache.retry(statusCode: 401, isConnectivityError: false) == .giveUp)
    }

    @Test func aDroppedConnectionTriesTheSameImageOnce() {
        #expect(ImageCache.retry(after: URLError(.timedOut)) == .sameURL)
        #expect(ImageCache.retry(after: URLError(.networkConnectionLost)) == .sameURL)
    }

    @Test func aBrokenImageOrServerErrorFallsBackToTheOriginalSize() {
        #expect(ImageCache.retry(statusCode: 500, isConnectivityError: false) == .originalSize)
        #expect(ImageCache.retry(statusCode: nil, isConnectivityError: false) == .originalSize)
    }

    @Test func aCancelledLoadIsNotTriedAgain() {
        #expect(ImageCache.retry(after: URLError(.cancelled)) == .giveUp)
        #expect(ImageCache.retry(after: CancellationError()) == .giveUp)
    }
}
