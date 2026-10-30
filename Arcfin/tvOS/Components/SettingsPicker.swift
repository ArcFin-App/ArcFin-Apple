// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A settings choice. A Picker on iPhone, iPad and Mac. On Apple TV a row that opens the
/// choices on a full-width page: as a popup menu it was narrow and its label stayed white on
/// the focused row's light platter, and the system's own picker page opened blank.
struct SettingsPicker<Value: Hashable>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> Text

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, selection: Binding<Value>,
         options: [Value], label: @escaping (Value) -> Text) {
        self.title = title
        self.detail = detail
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        NavigationLink {
            TVChoicePage(title: title, selection: $selection, options: options, label: label)
        } label: {
            TVChoiceRowLabel(title: title, detail: detail, value: label(selection))
        }
        .tvListRow()
    }
}

private struct TVChoiceRowLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let value: Text
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack {
            TVRowLabelText(title: title, detail: detail)
            Spacer()
            value
                .foregroundStyle(isFocused ? Color.black.opacity(0.65) : DT.Color.textSecondary)
        }
    }
}

/// The choices of a `SettingsPicker`, one per row, with a checkmark on the current one.
/// Picking one goes back.
struct TVChoicePage<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> Text
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    dismiss()
                } label: {
                    HStack {
                        label(option)
                        Spacer()
                        if option == selection {
                            Image(systemName: "checkmark")
                                .accessibilityLabel("Selected")
                        }
                    }
                }
                .tvListRow()
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .navigationTitle(title)
        .tvSettingsPage()
    }
}
