// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreImage
import JellyfinAPI
import SwiftUI

/// The average color of a remote image, used to tint a detail screen from its artwork.
enum AverageColor {
    static func load(from url: URL) async -> Color? {
        guard let data = await URLSession.arcfin.imageData(from: url),
              let image = CIImage(data: data)
        else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
