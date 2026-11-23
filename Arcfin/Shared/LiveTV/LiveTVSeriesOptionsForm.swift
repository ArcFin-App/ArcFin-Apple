// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// How a series is recorded: which episodes, on which channels and times, how much extra to
/// record either side, and how many to keep. Pickers and toggles only, so it works with a
/// remote as well as touch and a pointer.
struct LiveTVSeriesOptionsForm: View {
    @Binding var options: LiveTVSeriesOptions

    private static let paddingChoices = [0, 1, 2, 5, 10, 15, 30, 60]
    private static let keepChoices = [0, 1, 2, 3, 5, 10, 20]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("New Episodes Only", isOn: $options.recordNewOnly)
            Toggle("Any Channel", isOn: $options.recordAnyChannel)
            Toggle("Any Time", isOn: $options.recordAnyTime)
            picker("Start Early", selection: $options.startEarlyMinutes, choices: Self.paddingChoices)
            picker("Keep Recording After", selection: $options.endLateMinutes, choices: Self.paddingChoices)
            Picker("Keep", selection: $options.keepUpTo) {
                ForEach(Self.keepChoices, id: \.self) { count in
                    Text(count == 0 ? String(localized: "All Episodes") : String(localized: "Latest \(count)")).tag(count)
                }
            }
            .pickerStyle(.menu)
        }
        .tint(DT.Color.accent)
    }

    private func picker(_ title: LocalizedStringKey, selection: Binding<Int>, choices: [Int]) -> some View {
        Picker(title, selection: selection) {
            ForEach(choices, id: \.self) { minutes in
                Text(minutes == 0 ? String(localized: "Off") : String(localized: "\(minutes) min")).tag(minutes)
            }
        }
        .pickerStyle(.menu)
    }
}

/// A series recording's options, loaded from the server, changed and saved. Each platform shows
/// it in its own kind of sheet.
struct LiveTVSeriesEditor: View {
    let model: LiveTVModel
    let seriesTimer: LiveTVSeriesTimer
    let close: () -> Void

    @Environment(AuthManager.self) private var authManager
    @State private var options: LiveTVSeriesOptions?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(seriesTimer.name)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                if let channel = seriesTimer.channelName {
                    Text(channel)
                        .font(.system(.subheadline))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            if let binding = Binding($options) {
                LiveTVSeriesOptionsForm(options: binding)
                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel, action: close)
                        .buttonStyle(.glass)
                    Button {
                        guard let options else { return }
                        isSaving = true
                        Task {
                            if await model.save(options, for: seriesTimer, authManager: authManager) { close() }
                            isSaving = false
                        }
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                    .disabled(isSaving)
                }
                .controlSize(.large)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task {
            options = await model.options(for: seriesTimer, authManager: authManager) ?? LiveTVSeriesOptions(
                recordNewOnly: seriesTimer.recordNewOnly, recordAnyChannel: seriesTimer.recordAnyChannel,
                recordAnyTime: seriesTimer.recordAnyTime)
        }
    }
}
