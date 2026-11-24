// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import CoreVideo

/// Finds black bars baked into a trailer's picture (a wide film letterboxed in a 16:9 file,
/// say), so the hero can zoom just far enough to crop them off.
nonisolated enum TrailerLetterbox {
    /// The picture inside the bars, in unit coordinates and always centred: bars only count
    /// when both sides have them, so a dark sky or a dark edge of a scene is never cropped.
    /// nil while the frame is mostly black, like the fade at a trailer's start.
    static func pictureRect(in buffer: CVPixelBuffer) -> CGRect? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return nil }
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        func isDark(_ x: Int, _ y: Int) -> Bool {
            let pixel = pixels + y * bytesPerRow + x * 4
            return max(pixel[0], pixel[1], pixel[2]) <= darkLevel
        }
        let xStep = max(1, width / 64), yStep = max(1, height / 64)
        func rowIsDark(_ y: Int) -> Bool { stride(from: 0, to: width, by: xStep).allSatisfy { isDark($0, y) } }
        func columnIsDark(_ x: Int) -> Bool { stride(from: 0, to: height, by: yStep).allSatisfy { isDark(x, $0) } }

        var top = 0
        while top < height, rowIsDark(top) { top += 1 }
        var bottom = 0
        while bottom < height - top, rowIsDark(height - 1 - bottom) { bottom += 1 }
        var left = 0
        while left < width, columnIsDark(left) { left += 1 }
        var right = 0
        while right < width - left, columnIsDark(width - 1 - right) { right += 1 }

        guard let inset = bars(top, bottom, of: height),
              let sideInset = bars(left, right, of: width) else { return nil }
        return CGRect(x: sideInset, y: inset, width: 1 - 2 * sideInset, height: 1 - 2 * inset)
    }

    /// Where to put a video of `videoSize` so that `picture` fills `bounds`, cropping the rest.
    /// With the whole frame as the picture, this is the same as aspect fill.
    static func frame(videoSize: CGSize, picture: CGRect, filling bounds: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, picture.width > 0, picture.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = max(bounds.width / (videoSize.width * picture.width),
                        bounds.height / (videoSize.height * picture.height))
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.width / 2 - size.width * picture.midX,
                      y: bounds.height / 2 - size.height * picture.midY,
                      width: size.width, height: size.height)
    }

    /// Two measurements close enough to be the same bars.
    static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01
    }

    private static let darkLevel: UInt8 = 24

    /// The share of `length` to crop from each side, 0 when there are no bars to crop, or nil
    /// when the frame is mostly dark and can't be judged.
    private static func bars(_ start: Int, _ end: Int, of length: Int) -> Double? {
        let first = Double(start) / Double(length), second = Double(end) / Double(length)
        guard first + second < 0.6 else { return nil }
        let inset = min(first, second)
        // Uneven edges are the scene, not bars; slivers aren't worth a zoom.
        guard abs(first - second) < 0.03, inset >= 0.01 else { return 0 }
        return inset
    }
}
