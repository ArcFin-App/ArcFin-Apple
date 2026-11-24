// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A time of day as "HH:mm".
struct TimeOfDayRow: View {
    let title: LocalizedStringKey
    @Binding var time: String

    init(_ title: LocalizedStringKey, time: Binding<String>) {
        self.title = title
        self._time = time
    }

    var body: some View {
        DatePicker(title, selection: Binding(get: { ClockTime.date(time) }, set: { time = ClockTime.string($0) }),
                   displayedComponents: .hourAndMinute)
    }
}

/// A few lines of pasted key text.
struct KeyTextEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.footnote, design: .monospaced))
            .autocorrectionDisabled()
            .frame(minHeight: 120)
    }
}

/// A day and time, within `range`.
struct DateTimeRow: View {
    let title: LocalizedStringKey
    @Binding var date: Date
    let range: ClosedRange<Date>

    var body: some View {
        DatePicker(title, selection: $date, in: range, displayedComponents: [.date, .hourAndMinute])
    }
}

/// The Mac has no pull to refresh, so the live screens have a Refresh button.
enum AdminRefresh {
    static let showsButton = true
}
