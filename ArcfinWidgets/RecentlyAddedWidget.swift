// SPDX-License-Identifier: AGPL-3.0-or-later

import WidgetKit
import SwiftUI
import LiveActivityKit

struct RecentlyAddedEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSnapshot.Item]
}

struct RecentlyAddedProvider: TimelineProvider {
    private static let sample = RecentlyAddedEntry(date: Date(), items: (1...12).map {
        .init(id: "sample-\($0)", title: "New Title", subtitle: "2026", progress: 0, posterFileName: nil)
    })

    func placeholder(in context: Context) -> RecentlyAddedEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping (RecentlyAddedEntry) -> Void) {
        completion(context.isPreview ? Self.sample : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentlyAddedEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .after(Date().addingTimeInterval(60 * 60))))
    }

    private func currentEntry() -> RecentlyAddedEntry {
        RecentlyAddedEntry(date: Date(), items: WidgetSnapshotStore.load()?.recentlyAdded ?? [])
    }
}

/// The poster fills the space it's given, so a filled picture can't push the grid out.
private struct Poster: View {
    let item: WidgetSnapshot.Item

    var body: some View {
        Color.clear
            .overlay {
                if let image = artwork(item.posterFileName) {
                    image
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.fill.tertiary)
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct RecentlyAddedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentlyAddedEntry

    var body: some View {
        if entry.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "sparkles.tv").font(.largeTitle)
                Text("Nothing new yet").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            switch family {
            case .systemSmall: small
            case .systemLarge: grid(columns: 4, rows: 2, titled: true)
            case .systemExtraLarge: grid(columns: 6, rows: 2, titled: true)
            default: grid(columns: 4, rows: 1, titled: false)
            }
        }
    }

    /// The newest poster fills the widget.
    @ViewBuilder
    private var small: some View {
        if let item = entry.items.first {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New").font(.caption2.weight(.heavy)).textCase(.uppercase).opacity(0.8)
                    Text(item.title).font(.footnote.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
                    if let year = item.subtitle { Text(year).font(.caption2).opacity(0.8) }
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .widgetURL(playURL(item))
            .containerBackground(for: .widget) {
                if let image = artwork(item.posterFileName) {
                    image.resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
            }
        }
    }

    /// Posters sized to the room there is, across and down, with their names under them in
    /// the bigger sizes.
    private func grid(columns: Int, rows: Int, titled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recently Added", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let spacing: CGFloat = 8, caption: CGFloat = titled ? 18 : 0
                let across = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
                let down = ((geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows) - caption) * 2 / 3
                let width = max(min(across, down), 0)
                Grid(alignment: .topLeading, horizontalSpacing: spacing, verticalSpacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                if index < entry.items.count {
                                    let item = entry.items[index]
                                    Link(destination: playURL(item)) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Poster(item: item).frame(width: width, height: width * 3 / 2)
                                            if titled {
                                                Text(item.title).font(.caption2.weight(.medium)).lineLimit(1)
                                                    .frame(width: width, height: caption - 2, alignment: .leading)
                                            }
                                        }
                                    }
                                } else {
                                    Color.clear.frame(width: width, height: width * 3 / 2 + caption)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct RecentlyAddedWidget: Widget {
    let kind = "RecentlyAddedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentlyAddedProvider()) { entry in
            RecentlyAddedWidgetView(entry: entry)
        }
        .configurationDisplayName("Recently Added")
        .description("See the newest movies and shows on your server.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .notForCarPlay()
    }
}
