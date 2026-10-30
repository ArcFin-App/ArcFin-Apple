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
        Picker(selection: $selection) {
            ForEach(options, id: \.self) { label($0).tag($0) }
        } label: {
            TVRowLabelText(title: title, detail: detail)
        }
    }
}
