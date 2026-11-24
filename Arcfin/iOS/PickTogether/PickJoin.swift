// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Vision
import VisionKit
import CoreImage.CIFilterBuiltins
import JellyfinAPI

/// A crisp QR code for a short text.
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(uiImage: image)
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

    static func render(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Joins a session from its QR code, scanned with the camera.
struct PickScanView: View {
    @Bindable var model: PickTogetherModel
    var joined: () -> Void

    /// Read once: the start screen reads it on every redraw.
    static let isAvailable = DataScannerViewController.isSupported

    @State private var scanned = false

    var body: some View {
        ZStack(alignment: .bottom) {
            PickCodeScanner { code in
                guard !scanned else { return }
                scanned = true
                Task {
                    await model.join(code: code)
                    if model.state != nil { joined() } else { scanned = false }
                }
            }
            .ignoresSafeArea()
            Text(scanned ? "Joining…" : "Point the camera at the QR code on the phone or iPad that started the session.")
                .font(DT.Font.callout)
                .multilineTextAlignment(.center)
                .padding(DT.Spacing.md)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .padding(DT.Spacing.lg)
        }
        .navigationTitle("Scan the Code")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The camera, looking for a QR code with a code in it: a Pick Together one by default
/// (arcfin://pick/<code>, or just a code), or whatever `parse` reads.
struct PickCodeScanner: UIViewControllerRepresentable {
    var parse: (String) -> String? = PickTogetherClient.code(from:)
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parse: parse, onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parse: (String) -> String?
        let onFound: (String) -> Void

        init(parse: @escaping (String) -> String?, onFound: @escaping (String) -> Void) {
            self.parse = parse
            self.onFound = onFound
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in items {
                guard let text = barcode.payloadStringValue, let code = parse(text) else { continue }
                onFound(code)
                return
            }
        }
    }
}
