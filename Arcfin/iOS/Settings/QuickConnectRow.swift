// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Vision
import VisionKit

/// Signs another device in with this account, typed straight into Settings under Your Profile.
struct QuickConnectRow: View {
    @Environment(AuthManager.self) private var authManager
    @State private var quickConnect = QuickConnectModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A Label, as the Your Profile row above uses, so the icon gets the same size.
            Label {
                HStack(spacing: 10) {
                    TextField("Quick Connect", text: $quickConnect.code)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button {
                        quickConnect.authorize(authManager: authManager)
                    } label: {
                        if quickConnect.isAuthorizing { ProgressView().scaleEffect(0.8) }
                        else { Text("Authorize") }
                    }
                    .disabled(quickConnect.code.isEmpty || quickConnect.isAuthorizing)
                }
            } icon: {
                Image(systemName: "number.square")
                    .foregroundStyle(DT.Color.accent)
                    .frame(width: 22)
            }
            if let quickConnectResult = quickConnect.result {
                Text(quickConnectResult)
                    .font(.caption)
                    .foregroundStyle(quickConnectResult.hasPrefix("✓") ? DT.Color.palette("10b981") : DT.Color.palette("F43F5E"))
            }
        }
    }
}

/// Settings › Scan Apple TV Code: its own row under Quick Connect, so it's easy to hit and
/// a tap can't reach Authorize instead.
struct ScanAppleTVCodeRow: View {
    @State private var isScanning = false

    var body: some View {
        if QuickConnectScanner.isAvailable {
            Button { isScanning = true } label: {
                Label {
                    Text("Scan Apple TV Code")
                        .foregroundStyle(DT.Color.textPrimary)
                } icon: {
                    Image(systemName: "qrcode.viewfinder")
                        .foregroundStyle(DT.Color.accent)
                        .frame(width: 22)
                }
            }
            .sheet(isPresented: $isScanning) { scannerSheet }
        }
    }

    private var scannerSheet: some View {
        NavigationStack {
            QuickConnectScanner { url in
                isScanning = false
                _ = QuickConnectApproval.shared.open(url)
            }
            .ignoresSafeArea()
            .navigationTitle("Scan Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isScanning = false } }
            }
        }
    }
}

/// The camera, looking for the QR code an Apple TV shows on its Quick Connect screen.
private struct QuickConnectScanner: UIViewControllerRepresentable {
    let onFound: (URL) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (URL) -> Void
        private var found = false

        init(onFound: @escaping (URL) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in items {
                guard !found, let text = code.payloadStringValue, let url = URL(string: text),
                      QuickConnectLink.parse(url) != nil else { continue }
                found = true
                scanner.stopScanning()
                onFound(url)
            }
        }
    }
}
