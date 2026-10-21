// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct LicensesView: View {
    private struct License: Identifiable {
        let id = UUID()
        let name: String
        let license: String
        let url: String
        let note: String?
    }

    private let licenses: [License] = [
        License(name: "libVLC (via SwiftVLC)", license: "LGPL-2.1", url: "https://code.videolan.org/videolan/vlc",
                note: "Provides the VLC playback engine option. LGPL permits linking from closed-source apps."),
        License(name: "SwiftVLC", license: "MIT", url: "https://github.com/harflabs/SwiftVLC", note: nil),
        License(name: "The Composable Architecture", license: "MIT", url: "https://github.com/pointfreeco/swift-composable-architecture", note: nil),
        License(name: "Nuke", license: "MIT", url: "https://github.com/kean/Nuke", note: nil),
        License(name: "swift-openapi-runtime", license: "Apache 2.0", url: "https://github.com/apple/swift-openapi-runtime", note: nil),
        License(name: "swift-openapi-urlsession", license: "Apache 2.0", url: "https://github.com/apple/swift-openapi-urlsession", note: nil),
        License(name: "swift-openapi-generator", license: "Apache 2.0", url: "https://github.com/apple/swift-openapi-generator", note: nil),
        License(name: "Google Cast SDK", license: "Google APIs Terms of Service", url: "https://developers.google.com/terms/",
                note: "Powers Chromecast support. A prebuilt binary distributed under Google's own terms, not an open-source license."),
        License(name: "google-cast-sdk (SRGSSR)", license: "See repository", url: "https://github.com/SRGSSR/google-cast-sdk",
                note: "Community-maintained Swift Package Manager wrapper that packages Google's official Cast SDK for SPM projects — not a reimplementation of it."),
        // The Composable Architecture's own runtime dependencies — all pointfreeco/Apple
        // projects, and all actually linked into the app (not just used at compile time).
        License(name: "swift-case-paths", license: "MIT", url: "https://github.com/pointfreeco/swift-case-paths", note: nil),
        License(name: "swift-dependencies", license: "MIT", url: "https://github.com/pointfreeco/swift-dependencies", note: nil),
        License(name: "swift-navigation", license: "MIT", url: "https://github.com/pointfreeco/swift-navigation", note: nil),
        License(name: "swift-perception", license: "MIT", url: "https://github.com/pointfreeco/swift-perception", note: nil),
        License(name: "swift-sharing", license: "MIT", url: "https://github.com/pointfreeco/swift-sharing", note: nil),
        License(name: "swift-identified-collections", license: "MIT", url: "https://github.com/pointfreeco/swift-identified-collections", note: nil),
        License(name: "swift-custom-dump", license: "MIT", url: "https://github.com/pointfreeco/swift-custom-dump", note: nil),
        License(name: "swift-clocks", license: "MIT", url: "https://github.com/pointfreeco/swift-clocks", note: nil),
        License(name: "swift-concurrency-extras", license: "MIT", url: "https://github.com/pointfreeco/swift-concurrency-extras", note: nil),
        License(name: "combine-schedulers", license: "MIT", url: "https://github.com/pointfreeco/combine-schedulers", note: nil),
        License(name: "swift-collections", license: "Apache 2.0", url: "https://github.com/apple/swift-collections", note: nil),
        License(name: "YouTubePlayerKit", license: "MIT", url: "https://github.com/SvenTiigi/YouTubePlayerKit",
                note: "Plays a YouTube trailer in-app when a title has no local trailer file."),
        License(name: "YouTube API Services", license: "YouTube API Services Terms of Service", url: "https://developers.google.com/youtube/terms/api-services-terms-of-service",
                note: "Governs use of the embedded player above — not an open-source license."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(licenses) { entry in
                    let row = VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.name)
                                .font(.system(.footnote, design: .default, weight: .semibold))
                            Spacer()
                            Text(entry.license)
                                .font(.system(.caption, design: .default, weight: .medium))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        if let note = entry.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    #if os(tvOS)
                    // A bare .focusable() VStack was the only place in the app not using a
                    // real interactive control for a tvOS list row — focus-driven scrolling
                    // didn't reliably reach it, especially toward the end of the list.
                    Button {} label: { row.frame(maxWidth: .infinity, alignment: .leading) }
                        .buttonStyle(.plain)
                    #else
                    row
                    #endif
                }
            } footer: {
                Text("Licenses and other third-party components Arcfin uses.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .navigationTitle("Licenses & Third-Party Notices")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
