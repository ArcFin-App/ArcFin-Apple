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
                    // The list lines a row's separator up with its first text, and a field's
                    // placeholder isn't one: the line started at Authorize instead. The
                    // placeholder is drawn as text behind the field, so it lines up as above.
                    ZStack(alignment: .leading) {
                        Text("Quick Connect")
                            .foregroundStyle(.tertiary)
                            .opacity(quickConnect.code.isEmpty ? 1 : 0)
                            .accessibilityHidden(true)
                        TextField(text: $quickConnect.code, prompt: Text(verbatim: "")) { Text("Quick Connect") }
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
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

/// Settings › Set Up Nearby Device: looks for a signed-out Apple TV, iPad or Mac on the network now,
/// rather than waiting for one to turn up (#481).
struct SetUpNearbyDeviceRow: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Button { AppServices.nearbySetup.findNearby(authManager: authManager) } label: {
            Label {
                Text("Set Up Nearby Device")
                    .foregroundStyle(DT.Color.textPrimary)
            } icon: {
                Image(systemName: "ipad.and.iphone")
                    .foregroundStyle(DT.Color.accent)
                    .frame(width: 22)
            }
        }
    }
}

/// The camera, looking for the QR code an Apple TV shows on its Quick Connect screen.
private struct QuickConnectScanner: UIViewControllerRepresentable {
    let onFound: (URL) -> Void

    /// Read once: Settings reads it on every redraw.
    static let isAvailable = DataScannerViewController.isSupported

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
