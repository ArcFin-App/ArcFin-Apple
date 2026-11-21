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
/// the thumbnail into a plain light box there. The space it's given sets its size and the
/// picture fills it: a filled picture on its own reports its full size and pushes the layout
/// out of the widget.
private struct Artwork: View {
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
                        Image(systemName: "play.rectangle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
    }
}

private struct ProgressBar: View {
    let progress: Double
    var tint: Color = .white

    var body: some View {
        ProgressView(value: progress)
            .progressViewStyle(.linear)
            .tint(tint)
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

/// "S2 · E5 · Episode name", or the year for a movie.
private func secondLine(_ item: WidgetSnapshot.Item) -> String {
    [item.subtitle, item.detail].compactMap { $0 }.joined(separator: " · ")
}

/// The picture fills it, with the title, the episode and how far in over a gradient.
private struct HeroCard: View {
    let item: WidgetSnapshot.Item
    var titleLines = 2

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(item: item)
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline).lineLimit(titleLines).minimumScaleFactor(0.85)
                if !secondLine(item).isEmpty {
                    Text(secondLine(item)).font(.caption.weight(.medium)).lineLimit(1).opacity(0.9)
                }
                ProgressBar(progress: item.progress).padding(.top, 2)
            }
            .foregroundStyle(.white)
            .padding(12)
        }
    }
}

/// A picture on top with the title, episode and progress under it: two of these fill a
/// medium widget.
private struct Card: View {
    let item: WidgetSnapshot.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Artwork(item: item)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .bottom) { ProgressBar(progress: item.progress).padding(6) }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(item.title).font(.caption.weight(.semibold)).lineLimit(1)
            if !secondLine(item).isEmpty {
                Text(secondLine(item)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small picture, the title and episode, and how far in.
private struct CompactRow: View {
    let item: WidgetSnapshot.Item

    var body: some View {
        HStack(spacing: 10) {
            Artwork(item: item)
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.footnote.weight(.semibold)).lineLimit(1)
                if !secondLine(item).isEmpty {
                    Text(secondLine(item)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                ProgressBar(progress: item.progress, tint: .accentColor).frame(maxWidth: 120)
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
        case .systemLarge: large
        case .systemExtraLarge: extraLarge
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: small
        }
    }

    /// The latest title fills it.
    @ViewBuilder
    private var small: some View {
        if let item = entry.items.first {
            Color.clear
                .widgetURL(playURL(item))
                .containerBackground(for: .widget) { HeroCard(item: item, titleLines: 3) }
        } else {
            EmptyState().containerBackground(.fill.tertiary, for: .widget)
        }
    }

    /// The two latest, side by side.
    @ViewBuilder
    private var medium: some View {
        if !entry.items.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                ForEach(entry.items.prefix(2)) { item in
                    Link(destination: playURL(item)) { Card(item: item) }
                }
                if entry.items.count == 1 { Spacer(minLength: 0).frame(maxWidth: .infinity) }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            EmptyState().containerBackground(.fill.tertiary, for: .widget)
        }
    }

    /// The latest title large across the top, the next three listed underneath.
    @ViewBuilder
    private var large: some View {
        if let hero = entry.items.first {
            VStack(alignment: .leading, spacing: 10) {
                Link(destination: playURL(hero)) {
                    HeroCard(item: hero)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(maxHeight: .infinity)
                upNext(entry.items.dropFirst().prefix(3))
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            EmptyState().containerBackground(.fill.tertiary, for: .widget)
        }
    }

    /// The latest title on the left, up to five more on the right.
    @ViewBuilder
    private var extraLarge: some View {
        if let hero = entry.items.first {
            HStack(alignment: .top, spacing: 16) {
                Link(destination: playURL(hero)) {
                    HeroCard(item: hero)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                upNext(entry.items.dropFirst().prefix(5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            EmptyState().containerBackground(.fill.tertiary, for: .widget)
        }
    }

    @ViewBuilder
    private func upNext(_ items: ArraySlice<WidgetSnapshot.Item>) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Up Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(items) { item in
                    Link(destination: playURL(item)) { CompactRow(item: item) }
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
                Text(secondLine(item))
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
