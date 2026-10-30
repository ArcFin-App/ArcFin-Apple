// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Not private — reused by ContentView's offline-mode flow for the same "On This Device"
// file picker outside of Browse.
struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // VLC opens containers AVFoundation never could — broadened past the old
        // AVFoundation-only list (.movie/.video/.mpeg4Movie/.quickTimeMovie) to include mkv.
        let types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi, .matroska]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // Access is started/stopped as a matched pair inside LocalPlayerView itself
            // (task/onDisappear), not here — starting it in both places would leave one
            // extra unmatched start once LocalPlayerView's single stop call runs.
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

private extension UTType {
    static let avi = UTType(filenameExtension: "avi") ?? .movie
    static let matroska = UTType(filenameExtension: "mkv") ?? .movie
}
