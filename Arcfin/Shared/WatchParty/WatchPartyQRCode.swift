// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import CoreImage.CIFilterBuiltins

/// A crisp QR code for a watch party's link, for phones to scan.
struct WatchPartyQRCode: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.black)
        }
    }

    static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
