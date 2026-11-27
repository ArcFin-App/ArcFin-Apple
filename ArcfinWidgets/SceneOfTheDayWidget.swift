// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import ImageIO
import LiveActivityKit
import SwiftUI
import WidgetKit

// Arcs' Scene of the Day on the Home Screen and Lock Screen. The app writes the scene
// (ArcsWidgetStore) when it loads it and removes it when Arcs, its setting or the profile's
// app-lock PIN says the widget shouldn't show one.

struct SceneOfTheDayEntry: TimelineEntry {
    let date: Date
    let scene: ArcsWidgetSnapshot?
}

struct SceneOfTheDayProvider: TimelineProvider {
    private static let sample = ArcsWidgetSnapshot(
        clipID: "sample", title: String(localized: "Your Favourite Show"), sceneLine: "S2 · E5",
        overview: String(localized: "A scene from your library, picked for you each day."), imageFileName: nil)

    func placeholder(in context: Context) -> SceneOfTheDayEntry { SceneOfTheDayEntry(date: .now, scene: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (SceneOfTheDayEntry) -> Void) {
        completion(SceneOfTheDayEntry(date: .now, scene: context.isPreview ? ArcsWidgetStore.load() ?? Self.sample : ArcsWidgetStore.load()))
    }

    /// The app reloads the widget when it loads a new scene; the hourly look only matters if
    /// the snapshot went away without a reload.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SceneOfTheDayEntry>) -> Void) {
        completion(Timeline(entries: [SceneOfTheDayEntry(date: .now, scene: ArcsWidgetStore.load())],
                            policy: .after(.now.addingTimeInterval(60 * 60))))
    }
}

/// The title's poster filling the space it's given, or a plain fill.
private struct ScenePoster: View {
    let fileName: String?

    var body: some View {
        Color.clear
            .overlay {
                if let image = Self.image(fileName) {
                    image.resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.fill.tertiary)
                        Image(systemName: "play.square.stack").font(.title2).foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
    }

    static func image(_ fileName: String?) -> Image? {
        guard let fileName, let url = ArcsWidgetStore.imageURL(fileName: fileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1)
    }
}

struct SceneOfTheDayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SceneOfTheDayEntry

    var body: some View {
        if let scene = entry.scene {
            switch family {
            case .accessoryRectangular: rectangular(scene)
            case .systemMedium: medium(scene)
            default: small(scene)
            }
        } else {
            placeholder
        }
    }

    private var heading: some View {
        Label("Scene of the Day", systemImage: "play.square.stack")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .lineLimit(1)
    }

    /// The poster fills it, with the title and scene over a gradient.
    private func small(_ scene: ArcsWidgetSnapshot) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                heading.opacity(0.85)
                Text(verbatim: scene.title).font(.footnote.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.85)
                if let line = scene.sceneLine { Text(verbatim: line).font(.caption2).lineLimit(1).opacity(0.85) }
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .widgetURL(scene.url)
        .containerBackground(for: .widget) { ScenePoster(fileName: scene.imageFileName) }
    }

    /// The poster on the left, the title, scene and what happens in it on the right.
    private func medium(_ scene: ArcsWidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            ScenePoster(fileName: scene.imageFileName)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    Image(systemName: "play.fill").font(.title3).foregroundStyle(.white).shadow(radius: 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                heading.foregroundStyle(.tint).widgetAccentable()
                Text(verbatim: scene.title).font(.headline).lineLimit(2)
                if let line = scene.sceneLine {
                    Text(verbatim: line).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let overview = scene.overview {
                    Text(verbatim: overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .widgetURL(scene.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func rectangular(_ scene: ArcsWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            heading.widgetAccentable()
            Text(verbatim: scene.title).font(.headline).lineLimit(1)
            if let line = scene.sceneLine { Text(verbatim: line).font(.caption).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(scene.url)
        .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var placeholder: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Label { Text(verbatim: "Arcs") } icon: { Image(systemName: "play.square.stack") }
                    .font(.headline)
                    .widgetAccentable()
                Text("Open Arcfin to see today's scene").font(.caption).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "play.square.stack").font(.largeTitle)
                Text(verbatim: "Arcs").font(.headline)
                Text("Open Arcfin to see today's scene")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(8)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct SceneOfTheDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ArcsWidgetStore.kind, provider: SceneOfTheDayProvider()) { entry in
            SceneOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Scene of the Day")
        .description("A scene from your library, picked for you each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .notForCarPlay()
    }
}
#endif
