// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A time of day as "HH:mm". Apple TV has no time picker, so it's a choice of quarter hours.
struct TimeOfDayRow: View {
    let title: LocalizedStringKey
    @Binding var time: String

    init(_ title: LocalizedStringKey, time: Binding<String>) {
        self.title = title
        self._time = time
    }

    private var options: [String] {
        let quarters = stride(from: 0, to: 24 * 60, by: 15).map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
        return quarters.contains(time) ? quarters : (quarters + [time]).sorted()
    }

    var body: some View {
        SettingsPicker(title, selection: $time, options: options) { value in
            Text(ClockTime.date(value), format: .dateTime.hour().minute())
        }
    }
}

/// Pasted key text. Apple TV has no multi-line editor.
struct KeyTextEditor: View {
    @Binding var text: String

    var body: some View {
        TextField("Private Key", text: $text)
            .font(.system(.footnote, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .tvListRow()
    }
}

/// A day and time, within `range`. Apple TV has no date picker, so it's a day and a quarter hour.
struct DateTimeRow: View {
    let title: LocalizedStringKey
    @Binding var date: Date
    let range: ClosedRange<Date>

    private var days: [Date] {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)
        var days: [Date] = []
        var day = first
        while day <= last {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? last.addingTimeInterval(1)
        }
        return days
    }

    private var day: Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: date) }, set: { combine(day: $0, time: ClockTime.string(date)) })
    }

    private var time: Binding<String> {
        Binding(get: { ClockTime.string(date) }, set: { combine(day: Calendar.current.startOfDay(for: date), time: $0) })
    }

    private func combine(day: Date, time: String) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: ClockTime.date(time))
        date = Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    var body: some View {
        SettingsPicker(title, selection: day, options: days.contains(day.wrappedValue) ? days : days + [day.wrappedValue]) { value in
            Text(value, format: .dateTime.weekday(.wide).day().month(.wide))
        }
        TimeOfDayRow("Time", time: time)
    }
}

/// Apple TV has no pull to refresh, so the live screens have a Refresh button.
enum AdminRefresh {
    static let showsButton = true
}
