// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Now, or a time up to 30 days ahead: for starting a watch party, and for the host moving one.
struct WatchPartyScheduleView: View {
    /// The title being picked, shown at the top when starting a party.
    var item: MediaItem?
    var officialRating: String?
    /// People already in the party, for their own start times while the host moves it.
    var others: [PartyPerson]
    let confirmTitle: LocalizedStringKey
    var done: (Date?) async -> Void

    @State private var later: Bool
    @State private var date: Date
    @State private var isSaving = false

    init(item: MediaItem? = nil, officialRating: String? = nil, initial: Date? = nil, others: [PartyPerson] = [],
         confirmTitle: LocalizedStringKey, done: @escaping (Date?) async -> Void) {
        self.item = item
        self.officialRating = officialRating
        self.others = others
        self.confirmTitle = confirmTitle
        self.done = done
        _later = State(initialValue: initial != nil)
        _date = State(initialValue: initial ?? Self.suggested)
    }

    /// The next whole hour at least an hour from now.
    private static var suggested: Date {
        let inAnHour = Date.now.addingTimeInterval(3600)
        return Calendar.current.nextDate(after: inAnHour, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? inAnHour
    }

    private var range: ClosedRange<Date> { Date.now...Date.now.addingTimeInterval(30 * 24 * 3600) }

    private var elsewhere: [(person: PartyPerson, zone: TimeZone)] {
        others.compactMap { person in PartyClock.zone(of: person, at: date).map { (person, $0) } }
    }

    var body: some View {
        Form {
            if let item {
                Section {
                    WatchPartyItemHeader(item: item, officialRating: officialRating)
                }
            }
            Section {
                Picker("When", selection: $later) {
                    Text("Now").tag(false)
                    Text("Later").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: later) { HapticManager.selection() }
            }
            if later {
                Section {
                    DatePicker("Starts", selection: $date, in: range, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                    ForEach(elsewhere, id: \.person.id) { entry in
                        LabeledContent(String(localized: "For \(entry.person.name)"),
                                       value: PartyClock.time(date, in: entry.zone))
                    }
                } footer: {
                    Text("The lobby opens 15 minutes before the start. People can join with the code any time before then, and get a notification when it opens.")
                }
            }
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) {
                    Task {
                        isSaving = true
                        await done(later ? date : nil)
                        isSaving = false
                    }
                }
                .disabled(isSaving)
            }
        }
        .tint(DT.Color.accent)
    }
}

/// The title a party is being made for: its poster or thumbnail and what it is.
private struct WatchPartyItemHeader: View {
    let item: MediaItem
    let officialRating: String?

    @Environment(AuthManager.self) private var authManager

    private var imageURL: URL? {
        guard let credential = authManager.state.credential else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: item.id, tag: item.primaryImageTag ?? "",
                                            type: .primary, fillWidth: 300, token: credential.accessToken)
    }

    private var isEpisode: Bool { item.type == .episode }

    private var details: String {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        if let ticks = item.runTimeTicks, ticks > 0 {
            parts.append(Duration.seconds(ticks / 10_000_000).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
        if let officialRating, !officialRating.isEmpty { parts.append(officialRating) }
        if let rating = item.communityRating, rating > 0 {
            parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))")
        }
        return parts.joined(separator: " · ")
    }

    private var episodeLine: String? {
        guard isEpisode else { return nil }
        let number = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap(\.self).joined(separator: " · ")
        return [item.seriesName, number.isEmpty ? nil : number].compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: DT.Spacing.md) {
            RetryingAsyncImage(url: imageURL, logCategory: "WatchParty") { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    DT.Color.backgroundTertiary
                    Image(systemName: isEpisode ? "tv" : "film")
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .frame(width: isEpisode ? 128 : 72, height: isEpisode ? 72 : 108)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DT.Spacing.xxs) {
                if let episodeLine, !episodeLine.isEmpty {
                    Text(episodeLine)
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Text(item.name)
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !details.isEmpty {
                    Text(details)
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Text("Start now, or pick a time and invite people to join before then.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DT.Spacing.xxs)
                Text("Others can join from any app with SyncPlay; you need Arcfin to host.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DT.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// Start times in other people's time zones.
enum PartyClock {
    /// The person's zone, when its clock reads differently from this device's at `date`.
    static func zone(of person: PartyPerson, at date: Date) -> TimeZone? {
        guard let id = person.timeZone, id != TimeZone.current.identifier, let zone = TimeZone(identifier: id),
              zone.secondsFromGMT(for: date) != TimeZone.current.secondsFromGMT(for: date) else { return nil }
        return zone
    }

    /// "Paris" for Europe/Paris, "New York" for America/New_York.
    static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier).replacingOccurrences(of: "_", with: " ")
    }

    /// The time there, with the weekday when it's another day there.
    static func time(_ date: Date, in zone: TimeZone) -> String {
        var here = Calendar.current
        var there = Calendar.current
        here.timeZone = .current
        there.timeZone = zone
        let sameDay = here.component(.day, from: date) == there.component(.day, from: date)
        var style: Date.FormatStyle = sameDay ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }
}
