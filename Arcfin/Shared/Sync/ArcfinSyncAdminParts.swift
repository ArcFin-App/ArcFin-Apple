// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Loading, or why it couldn't load, for an Arcfin for Everyone screen.
struct AdminPendingSection: View {
    let error: String?

    var body: some View {
        Section {
            if let error {
                Text(error)
                    .foregroundStyle(DT.Color.textSecondary)
                    .tvReadOnlyRow()
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .tvReadOnlyRow()
            }
        }
    }
}

/// The few lines at the top of a screen that say what it's for.
struct AdminIntroSection: View {
    let text: LocalizedStringKey

    var body: some View {
        Section {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(DT.Color.textSecondary)
                .tvReadOnlyRow()
        }
    }
}

enum AdminSyncError {
    static func message(_ error: Error) -> String {
        (error as? PickTogetherError)?.message
            ?? String(localized: "The server didn't take that. Check your connection, and that this profile is still an admin.")
    }

    static func loadMessage() -> String {
        String(localized: "Couldn't load this. Check your connection, and that this profile is still an admin.")
    }
}

extension View {
    /// The "Couldn't Do That" alert the Arcfin for Everyone screens share.
    func adminErrorAlert(_ message: Binding<String?>) -> some View {
        alert("Couldn't Do That", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
        .onChange(of: message.wrappedValue) { _, new in if new != nil { HapticManager.error() } }
    }
}

extension Array where Element == ArcfinSyncAdminUser {
    func name(of userID: String) -> String {
        first { ArcfinCompanionClient.normalized($0.userId) == ArcfinCompanionClient.normalized(userID) }?.name
            ?? String(localized: "Someone")
    }
}

/// A time of day as the plugin keeps it: "HH:mm", in 24 hours whatever the device's clock shows.
enum ClockTime {
    static func date(_ time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first.map { min(max($0, 0), 23) } ?? 0
        let minute = parts.dropFirst().first.map { min(max($0, 0), 59) } ?? 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    static func string(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// A short status in a capsule: Locked, a party's phase, how a session ended.
struct AdminBadge: View {
    let text: Text
    var isProminent = false

    init(_ title: LocalizedStringKey, isProminent: Bool = false) {
        self.text = Text(title)
        self.isProminent = isProminent
    }

    init(verbatim title: String, isProminent: Bool = false) {
        self.text = Text(verbatim: title)
        self.isProminent = isProminent
    }

    var body: some View {
        text
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(isProminent ? DT.Color.onAccent : DT.Color.textSecondary)
            .background(isProminent ? DT.Color.accent : DT.Color.textPrimary.opacity(0.1), in: Capsule())
    }
}

/// A whole number up to `maximum`; empty is nil.
struct WholeNumberRow: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var value: Int?
    let maximum: Int

    var body: some View {
        LabeledContent {
            TextField(title, text: Binding(
                get: { value.map(String.init) ?? "" },
                set: { text in
                    let digits = text.filter(\.isNumber).prefix(String(maximum).count)
                    value = digits.isEmpty ? nil : min(Int(digits) ?? 0, maximum)
                }), prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
        } label: {
            TVRowLabelText(title: title)
        }
        .tvListRow()
    }
}
