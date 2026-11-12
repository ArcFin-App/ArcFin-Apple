// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Settings › Downloads › Ignored: the movies and shows Smart Downloads leaves alone.
struct SmartDownloadsIgnoredView: View {
    @Environment(DownloadManager.self) private var downloadManager

    var body: some View {
        let titles = downloadManager.ignoredTitles.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
        List {
            if titles.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Ignored", systemImage: "nosign")
                } description: {
                    Text("Choose Ignore in Smart Downloads in a movie or show's menu, or on it in Downloads.")
                }
            } else {
                Section {
                    ForEach(titles, id: \.key) { id, name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Include") { downloadManager.setIgnored(id: id, name: name, ignored: false) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Include \(name) in Smart Downloads")
                        }
                    }
                } footer: {
                    Text("Smart Downloads doesn't download these, even when they're in Continue Watching or Next Up.")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Ignored")
    }
}

/// Settings › Downloads › Kept Downloaded: shows set to Keep Downloaded, with how many
/// episodes each keeps.
struct KeptDownloadedView: View {
    @Environment(DownloadManager.self) private var downloadManager

    var body: some View {
        let _ = downloadManager.keptShowsVersion
        let shows = DownloadManager.keptShows.sorted { $0.value.name.localizedStandardCompare($1.value.name) == .orderedAscending }
        List {
            if shows.isEmpty {
                ContentUnavailableView {
                    Label("No Shows Kept", systemImage: "arrow.down.circle.dotted")
                } description: {
                    Text("Choose Keep Downloaded in a show's menu to keep its next episodes downloaded.")
                }
            } else {
                Section {
                    ForEach(shows, id: \.key) { seriesId, show in
                        Picker(show.name, selection: Binding(
                            get: { show.episodeCount },
                            set: { downloadManager.setKeptShow(seriesId: seriesId, name: show.name, episodeCount: $0 == 0 ? nil : $0) }
                        )) {
                            Text("Off").tag(0)
                            ForEach([1, 2, 3, 5], id: \.self) { count in
                                Text(count == 1 ? "Next Episode" : "Next \(count) Episodes").tag(count)
                            }
                        }
                    }
                } footer: {
                    Text("These download straight away, outside the storage budget, and stop under 2 GB free.")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Kept Downloaded")
    }
}
