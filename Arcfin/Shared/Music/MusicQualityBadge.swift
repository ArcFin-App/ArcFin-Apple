// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// The song's format under the scrubber: "Lossless", "Hi-Res Lossless", "AAC 256 kbps", or
/// what it's converted to as it streams. Tapping it shows the file and the stream.
struct MusicQualityBadge: View {
    let song: MusicSong
    var tint: Color = .white
    @State private var format: MusicAudioFormat?
    @State private var showsDetails = false
    private var stream: MusicQueuePlayer.Stream? { AppServices.music.player.stream }

    @MainActor private static var known: [String: MusicAudioFormat] = [:]

    var body: some View {
        Button { showsDetails = true } label: {
            Label {
                Text(verbatim: summary)
            } icon: {
                Image(systemName: icon)
            }
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint.opacity(0.75))
            .background(tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(format == nil && stream == nil ? 0 : 1)
        .accessibilityHint("Shows the song's format")
        .task(id: song.id) { format = await Self.format(of: song) }
        .sheet(isPresented: $showsDetails) { details }
    }

    private static func format(of song: MusicSong) async -> MusicAudioFormat? {
        if let format = known[song.id] { return format }
        let format = try? await MusicAPI.call { try await $0.getAudioFormat(credential: $1, authHeader: $2, songId: song.id) }
        if let format = format ?? nil { known[song.id] = format }
        return format ?? nil
    }

    private var isConverted: Bool {
        if case .converted = stream { return true }
        return false
    }

    private var icon: String {
        if isConverted { return "arrow.triangle.2.circlepath" }
        return format?.isLossless == true ? "waveform" : "music.note"
    }

    private var summary: String {
        if case .converted(let kilobits) = stream {
            return kilobits.map { String(localized: "MP3 \($0) kbps") } ?? "MP3"
        }
        guard let format else { return "" }
        if format.isHighResolution { return String(localized: "Hi-Res Lossless") }
        if format.isLossless { return String(localized: "Lossless") }
        let codec = Self.codecName(format.codec ?? format.container)
        return format.bitrate.map { String(localized: "\(codec) \($0 / 1000) kbps") } ?? codec
    }

    private static func codecName(_ codec: String?) -> String {
        switch codec?.lowercased() {
        case "aac": "AAC"
        case "mp3": "MP3"
        case "opus": "Opus"
        case "vorbis": "Vorbis"
        case "flac": "FLAC"
        case "alac": "ALAC"
        case let other?: other.uppercased()
        case nil: "—"
        }
    }

    private var details: some View {
        NavigationStack {
            List {
                Section("File") {
                    LabeledContent("Format", value: Self.codecName(format?.codec ?? format?.container)).tvReadOnlyRow()
                    if let bitDepth = format?.bitDepth {
                        LabeledContent("Bit Depth", value: String(localized: "\(bitDepth)-bit")).tvReadOnlyRow()
                    }
                    if let sampleRate = format?.sampleRate {
                        LabeledContent("Sample Rate", value: String(localized: "\((Double(sampleRate) / 1000).formatted()) kHz"))
                            .tvReadOnlyRow()
                    }
                    if let bitrate = format?.bitrate {
                        LabeledContent("Bitrate", value: String(localized: "\(bitrate / 1000) kbps")).tvReadOnlyRow()
                    }
                    if let channels = format?.channels {
                        LabeledContent("Channels", value: channels == 2 ? String(localized: "Stereo")
                                       : channels == 1 ? String(localized: "Mono") : "\(channels)")
                            .tvReadOnlyRow()
                    }
                }
                Section("Playing") {
                    Text(playing).tvReadOnlyRow()
                }
            }
            .arcfinListStyle()
            .navigationTitle(Text(verbatim: song.name))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsDetails = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var playing: String {
        switch stream {
        case .saved: String(localized: "The downloaded file, as it is.")
        case .original: String(localized: "The server's file, as it is.")
        case .converted(let kilobits?): String(localized: "Converted by the server to MP3 at \(kilobits) kbps as it streams.")
        case .converted(nil): String(localized: "Converted by the server to MP3 as it streams.")
        case nil: String(localized: "Not playing yet.")
        }
    }
}
