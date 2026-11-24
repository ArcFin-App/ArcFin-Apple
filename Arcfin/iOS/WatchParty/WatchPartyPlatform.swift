// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

enum WatchPartyPlatform {
    static var canScan: Bool { PickScanView.isAvailable }

    static var joinBlurb: Text {
        Text("Pick something and invite people with a code, or join someone else's party by scanning its QR code or typing the code under it. When the host starts, the title plays in sync on every device.")
    }
}

typealias WatchPartyHub = WatchPartyJoinView
typealias WatchPartyLobbyLayout = StackedWatchPartyLobby

/// The time a party starts.
struct WatchPartyStartPicker: View {
    @Binding var date: Date
    let range: ClosedRange<Date>

    var body: some View {
        DatePicker("Starts", selection: $date, in: range, displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.graphical)
    }
}

extension View {
    /// Leave while in a party that's on, Close otherwise.
    func watchPartyCloseButton(leaves: Bool, leave: @escaping () -> Void, close: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if leaves {
                    Button("Leave", action: leave)
                } else {
                    Button("Close", action: close)
                }
            }
        }
    }

    func watchPartyConfirm(_ title: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(title, action: action)
                    .disabled(disabled)
            }
        }
    }

    func partyCodeInput() -> some View {
        textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
    }

    func watchPartySearchable(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        sectionSearchable(text: text, prompt: prompt)
    }

    /// Where Apple TV puts focus first.
    func watchPartyPrimary(_ isPrimary: Bool = true) -> some View {
        self
    }
}

/// A note that opens and closes.
struct WatchPartyDisclosure<Content: View, Label: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            label
        }
    }
}

extension View {
    func partyTextSelection() -> some View {
        textSelection(.enabled)
    }

    func partyListBackground() -> some View {
        scrollContentBackground(.hidden)
    }
}
