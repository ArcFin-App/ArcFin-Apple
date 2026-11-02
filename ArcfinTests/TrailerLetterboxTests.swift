// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreVideo
import Testing
@testable import Arcfin

struct TrailerLetterboxTests {
    /// A 160×90 frame, grey inside `picture` (in pixels) and black outside it.
    private func frame(picture: CGRect, brightness: UInt8 = 128) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 160, 90, kCVPixelFormatType_32BGRA, nil, &buffer)
        let frame = buffer!
        CVPixelBufferLockBaseAddress(frame, [])
        let base = CVPixelBufferGetBaseAddress(frame)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(frame)
        for y in 0..<90 {
            for x in 0..<160 {
                let inside = picture.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
                let pixel = base + y * bytesPerRow + x * 4
                pixel[0] = inside ? brightness : 0
                pixel[1] = inside ? brightness : 0
                pixel[2] = inside ? brightness : 0
                pixel[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(frame, [])
        return frame
    }

    @Test func fullPictureHasNoBars() {
        let rect = TrailerLetterbox.pictureRect(in: frame(picture: CGRect(x: 0, y: 0, width: 160, height: 90)))
        #expect(rect == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func findsLetterboxBars() throws {
        let rect = try #require(TrailerLetterbox.pictureRect(in: frame(picture: CGRect(x: 0, y: 9, width: 160, height: 72))))
        #expect(abs(rect.minY - 0.1) < 0.001)
        #expect(abs(rect.height - 0.8) < 0.001)
        #expect(rect.minX == 0)
    }

    @Test func findsPillarboxBars() throws {
        let rect = try #require(TrailerLetterbox.pictureRect(in: frame(picture: CGRect(x: 20, y: 0, width: 120, height: 90))))
        #expect(abs(rect.minX - 0.125) < 0.001)
        #expect(rect.minY == 0)
    }

    @Test func darkAtOneEdgeOnlyIsNotCropped() {
        let rect = TrailerLetterbox.pictureRect(in: frame(picture: CGRect(x: 0, y: 18, width: 160, height: 72)))
        #expect(rect == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func blackFrameCantBeJudged() {
        #expect(TrailerLetterbox.pictureRect(in: frame(picture: .zero)) == nil)
    }

    @Test func wholePictureFillsLikeAspectFill() {
        let rect = TrailerLetterbox.frame(videoSize: CGSize(width: 1920, height: 1080),
                                          picture: CGRect(x: 0, y: 0, width: 1, height: 1),
                                          filling: CGSize(width: 1000, height: 500))
        #expect(abs(rect.width - 1000) < 0.001)
        #expect(abs(rect.height - 562.5) < 0.001)
        #expect(abs(rect.midY - 250) < 0.001)
    }

    @Test func barsAreCroppedOutOfTheBounds() {
        let picture = CGRect(x: 0, y: 0.1, width: 1, height: 0.8)
        let bounds = CGSize(width: 1000, height: 562.5)
        let rect = TrailerLetterbox.frame(videoSize: CGSize(width: 1920, height: 1080), picture: picture, filling: bounds)
        // The picture's top and bottom edges land on (or beyond) the bounds' edges.
        #expect(rect.minY + rect.height * picture.minY <= 0.001)
        #expect(rect.minY + rect.height * picture.maxY >= bounds.height - 0.001)
        #expect(abs(rect.midX - 500) < 0.001)
    }
}
