// SPDX-License-Identifier: AGPL-3.0-or-later

import WidgetKit
import SwiftUI
import LiveActivityKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Timeline

struct ContinueWatchingEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSnapshot.Item]
}

struct ContinueWatchingProvider: TimelineProvider {
    private static let sample = ContinueWatchingEntry(date: Date(), items: [
        .init(id: "sample-1", title: "Continue Watching", subtitle: "S1E3 · Episode", progress: 0.4, posterFileName: nil),
        .init(id: "sample-2", title: "Up Next", subtitle: "2024", progress: 0.7, posterFileName: nil),
        .init(id: "sample-3", title: "Resume", subtitle: "2023", progress: 0.2, posterFileName: nil),
    ])

    func placeholder(in context: Context) -> ContinueWatchingEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping (ContinueWatchingEntry) -> Void) {
        completion(context.isPreview ? Self.sample : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueWatchingEntry>) -> Void) {
        // The app reloads timelines whenever Continue Watching changes; the periodic refresh
        // only covers a stale snapshot if the app hasn't run for a while.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> ContinueWatchingEntry {
        ContinueWatchingEntry(date: Date(), items: WidgetSnapshotStore.load()?.items ?? [])
    }
}

// MARK: - Shared pieces

private enum WidgetPalette {
    static let background = Color(red: 10 / 255, green: 10 / 255, blue: 15 / 255)
    static let accent = Color(red: 6 / 255, green: 182 / 255, blue: 212 / 255)
}

private func playURL(_ item: WidgetSnapshot.Item) -> URL {
    URL(string: "arcfin://play/\(item.id)") ?? URL(string: "arcfin://downloads")!
}

private func posterImage(_ fileName: String?) -> Image? {
    guard let fileName, let url = WidgetSnapshotStore.posterURL(fileName: fileName) else { return nil }
    #if canImport(UIKit)
    guard let image = UIImage(contentsOfFile: url.path) else { return nil }
    return Image(uiImage: image)
    #elseif canImport(AppKit)
    guard let image = NSImage(contentsOf: url) else { return nil }
    return Image(nsImage: image)
    #else
    return nil
    #endif
}

private struct PosterView: View {
    let item: WidgetSnapshot.Item

    var body: some View {
        if let image = posterImage(item.posterFileName) {
            image.resizable().scaledToFill()
        } else {
            ZStack {
                Color.white.opacity(0.08)
                Image(systemName: "film").font(.title2).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(WidgetPalette.accent).frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 3)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "play.circle").font(.title)
            Text("Nothing to resume").font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Views per family

struct ContinueWatchingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ContinueWatchingEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    @ViewBuilder
    private var small: some View {
        if let item = entry.items.first {
            ZStack(alignment: .bottomLeading) {
                PosterView(item: item)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.footnote.weight(.bold)).lineLimit(2)
                    ProgressBar(progress: item.progress)
                }
                .foregroundStyle(.white)
                .padding(10)
            }
            .widgetURL(playURL(item))
        } else {
            EmptyState()
        }
    }

    @ViewBuilder
    private var medium: some View {
        if entry.items.isEmpty {
            EmptyState()
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(entry.items.prefix(3)) { item in
                    Link(destination: playURL(item)) {
                        VStack(alignment: .leading, spacing: 4) {
                            PosterView(item: item)
                                .aspectRatio(2 / 3, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            ProgressBar(progress: item.progress)
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let item = entry.items.first {
            VStack(alignment: .leading, spacing: 2) {
                Label(item.title, systemImage: "play.fill")
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).lineLimit(1)
                }
                ProgressView(value: item.progress)
            }
            .widgetURL(playURL(item))
        } else {
            Label("Nothing to resume", systemImage: "play.circle").font(.footnote)
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let item = entry.items.first {
            Gauge(value: item.progress) {
                Image(systemName: "play.fill")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(playURL(item))
        } else {
            Image(systemName: "play.circle")
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let item = entry.items.first {
            Label("Resume \(item.title)", systemImage: "play.fill")
                .widgetURL(playURL(item))
        } else {
            Label("Nothing to resume", systemImage: "play.circle")
        }
    }
}

// MARK: - Widget

struct ContinueWatchingWidget: Widget {
    let kind = "ContinueWatchingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContinueWatchingProvider()) { entry in
            ContinueWatchingWidgetView(entry: entry)
                .containerBackground(WidgetPalette.background, for: .widget)
        }
        .configurationDisplayName("Continue Watching")
        .description("Pick up where you left off.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
