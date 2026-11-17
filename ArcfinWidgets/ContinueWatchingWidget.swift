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
        .init(id: "sample-1", title: "Continue Watching", subtitle: "S1 · E3", detail: "Pilot", progress: 0.4, posterFileName: nil),
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

func playURL(_ item: WidgetSnapshot.Item) -> URL {
    URL(string: "arcfin://play/\(item.id)") ?? URL(string: "arcfin://downloads")!
}

func artwork(_ fileName: String?) -> Image? {
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

/// Artwork keeps its colors in Tinted and Clear Home Screen modes. Without
/// `.fullColor` the system flattens an image to a single tint, which is what turned
/// the thumbnail into a plain light box there.
private struct Artwork: View {
    let item: WidgetSnapshot.Item

    var body: some View {
        if let image = artwork(item.posterFileName) {
            image
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        ProgressView(value: progress)
            .progressViewStyle(.linear)
            .tint(.white)
            .widgetAccentable()
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "play.circle").font(.largeTitle)
            Text("Nothing to resume").font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Title, then "S2 · E5" and the episode name; movies show just the year.
private struct ItemCaption: View {
    let item: WidgetSnapshot.Item
    var titleFont: Font = .headline

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title).font(titleFont).lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.caption.weight(.semibold)).lineLimit(1)
            }
            if let detail = item.detail {
                Text(detail).font(.caption).lineLimit(1).opacity(0.85)
            }
        }
    }
}

/// Image fills the whole widget with a legibility gradient under the text.
private struct HeroCard: View {
    let item: WidgetSnapshot.Item

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(item: item)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                ItemCaption(item: item)
                ProgressBar(progress: item.progress)
            }
            .foregroundStyle(.white)
            .padding(12)
        }
    }
}

private struct CompactRow: View {
    let item: WidgetSnapshot.Item

    var body: some View {
        HStack(spacing: 8) {
            Artwork(item: item)
                .frame(width: 64)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text([item.subtitle, item.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
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
        case .systemLarge, .systemExtraLarge: large
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    @ViewBuilder
    private var small: some View {
        if let item = entry.items.first {
            Color.clear
                .widgetURL(playURL(item))
                .containerBackground(for: .widget) { HeroCard(item: item) }
        } else {
            EmptyState().containerBackground(.fill.tertiary, for: .widget)
        }
    }

    @ViewBuilder
    private var medium: some View {
        if let hero = entry.items.first {
            HStack(spacing: 12) {
                Link(destination: playURL(hero)) {
                    HeroCard(item: hero)
                        .clipShape(ContainerRelativeShape())
                }
                if entry.items.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entry.items.dropFirst().prefix(2)) { item in
                            Link(destination: playURL(item)) { CompactRow(item: item) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            EmptyState().containerBackground(.fill.tertiary, for: .widget)
        }
    }

    /// The latest title large across the top, the next three listed underneath.
    @ViewBuilder
    private var large: some View {
        if let hero = entry.items.first {
            VStack(alignment: .leading, spacing: 12) {
                Link(destination: playURL(hero)) {
                    HeroCard(item: hero)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(maxHeight: .infinity)
                if entry.items.count > 1 {
                    Text("Up Next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entry.items.dropFirst().prefix(3)) { item in
                            Link(destination: playURL(item)) { CompactRow(item: item) }
                        }
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            EmptyState().containerBackground(.fill.tertiary, for: .widget)
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let item = entry.items.first {
            VStack(alignment: .leading, spacing: 2) {
                Label(item.title, systemImage: "play.fill")
                    .font(.headline)
                    .lineLimit(1)
                Text([item.subtitle, item.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .lineLimit(1)
                ProgressView(value: item.progress)
            }
            .widgetURL(playURL(item))
            .containerBackground(.clear, for: .widget)
        } else {
            Label("Nothing to resume", systemImage: "play.circle").font(.footnote)
                .containerBackground(.clear, for: .widget)
        }
    }

    @ViewBuilder
    private var circular: some View {
        Group {
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
        .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var inline: some View {
        if let item = entry.items.first {
            Label("\(item.title)\(item.subtitle.map { " \($0)" } ?? "")", systemImage: "play.fill")
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
        }
        .configurationDisplayName("Continue Watching")
        .description("Pick up where you left off.")
        .supportedFamilies(families)
        .notForCarPlay()
    }

    /// The Lock Screen sizes exist on iOS only.
    private var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
         .accessoryRectangular, .accessoryCircular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #endif
    }
}
