import SwiftUI

struct OpenSourceLicensesView: View {
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
    ]

    var body: some View {
        List {
            Section {
                ForEach(licenses) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.name)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(entry.license)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        if let note = entry.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Arcfin uses these open-source libraries. Each remains under its own license; using them does not require Arcfin's own source to be published.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .navigationTitle("Open Source Licenses")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
