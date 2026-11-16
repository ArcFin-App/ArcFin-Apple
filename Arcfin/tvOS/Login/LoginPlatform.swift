// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import CoreImage.CIFilterBuiltins

extension View {
    func loginFieldInput(_ kind: LoginFieldKind) -> some View {
        self
    }

    func loginBackButtonPadding() -> some View {
        padding(.horizontal, 16)
    }

    func quickConnectCodeSelection() -> some View {
        self
    }

    /// The code with a QR code beside it: an iPhone's Camera opens it in Arcfin, which signs
    /// this Apple TV in after asking.
    func quickConnectQRCode(_ link: URL?) -> some View {
        HStack(spacing: 48) {
            self
            if let link, let image = QuickConnectQR.image(for: link) {
                VStack(spacing: 16) {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 260, height: 260)
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text("Or scan with your iPhone's Camera")
                        .font(.footnote)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
    }

    func seerrPromptNotNowButton(_ action: @escaping () -> Void) -> some View {
        self
    }

    // .roundedBorder is unavailable on tvOS — its SecureField already renders
    // with the system's own default appearance there, no style needed.
    func seerrPasswordFieldStyle(onSubmit: @escaping () -> Void) -> some View {
        self
    }
}

private enum QuickConnectQR {
    static func image(for link: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
