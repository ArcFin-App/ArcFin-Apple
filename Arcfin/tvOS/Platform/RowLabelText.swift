// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

// Toggle(_:isOn:) and Picker(_:selection:) render their string label through their own
// internal Text, which on tvOS keeps the system's default color regardless of
// foregroundStyle applied from outside the control — unreadable once the row's focus
// platter goes light. Use this as the label content (Toggle(isOn:label:) /
// Picker(selection:label:)) instead of the string convenience initializer wherever a tvOS
// row needs its text to read in the app's text color while focused. A plain, unstyled Text
// on every other platform, so call sites don't need their own platform guard.
/// `detail` is the line or two under a setting that says what it does.
struct TVRowLabelText: View {
    let title: Text
    var detail: LocalizedStringKey? = nil
    @Environment(\.isFocused) private var isFocused

    init(title: LocalizedStringKey, detail: LocalizedStringKey? = nil) {
        self.title = Text(title)
        self.detail = detail
    }

    init(verbatim title: String, detail: LocalizedStringKey? = nil) {
        self.title = Text(verbatim: title)
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .foregroundStyle(isFocused ? Color.black : DT.Color.textPrimary)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isFocused ? Color.black.opacity(0.65) : DT.Color.textSecondary)
            }
        }
        .animation(DT.Animation.fast, value: isFocused)
    }
}
