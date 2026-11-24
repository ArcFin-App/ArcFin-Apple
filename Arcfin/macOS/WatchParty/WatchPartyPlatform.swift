// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

enum WatchPartyPlatform {
    /// The Mac has no code scanner; the code is typed.
    static let canScan = false

    static var joinBlurb: Text {
        Text("Pick something and invite people with a code, or join someone else's party by typing the code under its QR code. When the host starts, the title plays in sync on every device.")
    }
}

typealias WatchPartyHub = WatchPartyJoinView
typealias WatchPartyLobbyLayout = StackedWatchPartyLobby

/// Never opened here: the Mac has no Scan a Code button.
struct WatchPartyScanView: View {
    let model: WatchPartyModel
    var joined: () -> Void

    var body: some View { EmptyView() }
}

/// The time a party starts.
struct WatchPartyStartPicker: View {
    @Binding var date: Date
    let range: ClosedRange<Date>

    /// A calendar for the day, and hour, minute and AM/PM fields for the time: the graphical
    /// style's time is a clock face.
    var body: some View {
        DatePicker("Day", selection: $date, in: range, displayedComponents: .date)
            .datePickerStyle(.graphical)
        DatePicker("Time", selection: $date, in: range, displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
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
        autocorrectionDisabled()
    }

    /// A field over the list: in a sheet there's no window toolbar for a search field to go in.
    func watchPartySearchable(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        safeAreaInset(edge: .top) {
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, DT.Spacing.md)
                .padding(.vertical, DT.Spacing.sm)
        }
    }

    /// Where Apple TV puts focus first.
    func watchPartyPrimary(_ isPrimary: Bool = true) -> some View {
        self
    }

    /// A watch party in a sheet sized for the window.
    func watchPartySheet(_ launch: Binding<WatchPartyLaunch?>, play: @escaping (PlaybackRequest) -> Void) -> some View {
        sheet(item: launch) { party in
            WatchPartyView(launch: party.launch, play: play)
                .frame(minWidth: 560, idealWidth: 620, minHeight: 640, idealHeight: 760)
        }
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
