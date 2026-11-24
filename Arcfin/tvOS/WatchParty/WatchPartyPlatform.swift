// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

enum WatchPartyPlatform {
    /// Apple TV has no code scanner; the code is typed or dictated.
    static let canScan = false

    static var joinBlurb: Text {
        Text("Pick something and invite people with a code, or join someone else's party by typing the code under its QR code. When the host starts, the title plays in sync on every device.")
    }
}

/// Never opened here: Apple TV has no Scan a Code button.
struct WatchPartyScanView: View {
    let model: WatchPartyModel
    var joined: () -> Void

    var body: some View { EmptyView() }
}

/// The lobby across the screen: the title and the code to join with on the left, who's here
/// and the controls on the right. Each column is its own focus area, so the remote moves
/// between them from any height.
struct WatchPartyLobbyLayout<Heading: View, Schedule: View, Invite: View, Rest: View>: View {
    var focusKey: String
    @ViewBuilder var heading: Heading
    @ViewBuilder var schedule: Schedule
    @ViewBuilder var invite: Invite
    @ViewBuilder var rest: Rest

    @Namespace private var scope
    @Environment(\.resetFocus) private var resetFocus

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            column {
                heading
                invite
            }
            column {
                schedule
                rest
            }
        }
        .padding(.horizontal, 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.watchPartyFocusScope, scope)
        .focusScope(scope)
        .toolbar(.hidden, for: .navigationBar)
        // The control that had focus can go when the party moves on (the Ready toggle once it
        // starts); focus doesn't find the next one by itself.
        .onChange(of: focusKey, initial: true) { resetFocus(in: scope) }
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: DT.Spacing.lg) { content() }
                .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity)
        .focusSection()
    }
}

/// The time a party starts: a day in the next 30, and a time on it every quarter hour.
struct WatchPartyStartPicker: View {
    @Binding var date: Date
    let range: ClosedRange<Date>

    private var calendar: Calendar { .current }

    private var days: [Date] {
        let first = calendar.startOfDay(for: range.lowerBound)
        return (0...30).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
            .filter { $0 <= range.upperBound }
    }

    private var day: Binding<Date> {
        Binding {
            calendar.startOfDay(for: date)
        } set: { day in
            date = clamped(day.addingTimeInterval(date.timeIntervalSince(calendar.startOfDay(for: date))))
        }
    }

    private var minute: Binding<Int> {
        Binding {
            Int(date.timeIntervalSince(calendar.startOfDay(for: date)) / 60) / 15 * 15
        } set: { minute in
            date = clamped(calendar.startOfDay(for: date).addingTimeInterval(Double(minute) * 60))
        }
    }

    var body: some View {
        Picker("Day", selection: day) {
            ForEach(days, id: \.self) { day in
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).tag(day)
            }
        }
        // A menu in place: the pushed page a picker opens was blank inside the party's cover.
        .pickerStyle(.menu)
        Picker("Time", selection: minute) {
            ForEach(Array(stride(from: 0, to: 24 * 60, by: 15)), id: \.self) { minute in
                Text(calendar.startOfDay(for: date).addingTimeInterval(Double(minute) * 60)
                    .formatted(date: .omitted, time: .shortened)).tag(minute)
            }
        }
        .pickerStyle(.menu)
    }

    /// Within the 30 days, and on a quarter hour when the earliest is now.
    private func clamped(_ value: Date) -> Date {
        if value > range.upperBound { return range.upperBound }
        guard value < range.lowerBound else { return value }
        let quarter: Double = 15 * 60
        return Date(timeIntervalSinceReferenceDate: (range.lowerBound.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
    }
}

extension EnvironmentValues {
    @Entry var watchPartyFocusScope: Namespace.ID?
}

extension View {
    /// Back on the remote: the same Leave or Close as the other platforms' toolbar button.
    func watchPartyCloseButton(leaves: Bool, leave: @escaping () -> Void, close: @escaping () -> Void) -> some View {
        onExitCommand { leaves ? leave() : close() }
    }

    /// The page's action under it, focused first.
    func watchPartyConfirm(_ title: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
        modifier(PartyConfirmButton(title: title, disabled: disabled, action: action))
    }

    func partyCodeInput() -> some View {
        textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
    }

    func watchPartySearchable(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        searchable(text: text, prompt: prompt)
    }

    /// Where focus goes first in the lobby, and goes back to when the controls change.
    func watchPartyPrimary(_ isPrimary: Bool = true) -> some View {
        modifier(PartyPrimaryFocus(isPrimary: isPrimary))
    }
}

private struct PartyPrimaryFocus: ViewModifier {
    let isPrimary: Bool
    @Environment(\.watchPartyFocusScope) private var scope

    func body(content: Content) -> some View {
        if let scope {
            content.prefersDefaultFocus(isPrimary, in: scope)
        } else {
            content
        }
    }
}

private struct PartyConfirmButton: ViewModifier {
    let title: LocalizedStringKey
    let disabled: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                Button(action: action) {
                    TVDetailButtonLabel(icon: "checkmark", text: title, isPrimary: true)
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .focused($isFocused)
                .disabled(disabled)
                .frame(width: 560)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .focusSection()
            }
            .defaultFocus($isFocused, true)
    }
}

/// A note that opens and closes: one button, so the remote reaches the whole note.
struct WatchPartyDisclosure<Content: View, Label: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label

    var body: some View {
        Button { isExpanded.toggle() } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    label
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(DT.Color.textSecondary)
                        .accessibilityHidden(true)
                }
                if isExpanded { content }
            }
            .contentShape(Rectangle())
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.lg, prominent: false)
    }
}

extension View {
    func partyTextSelection() -> some View {
        self
    }

    func partyListBackground() -> some View {
        self
    }
}

extension View {
    /// The watch party screen over everything, on the page's own background: a cover is
    /// transparent on Apple TV, so the screen underneath showed through.
    func watchPartyCover(_ party: Binding<WatchPartyLaunch?>, play: @escaping (PlaybackRequest) -> Void) -> some View {
        fullScreenCover(item: party) { party in
            WatchPartyView(launch: party.launch, play: play)
                .screenBackground()
        }
    }
}
