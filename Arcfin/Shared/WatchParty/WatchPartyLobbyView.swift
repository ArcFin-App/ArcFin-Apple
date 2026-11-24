// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The lobby: the title, the code and QR code to join with, and who's in and ready. The host
/// starts it; then everyone's player opens in one SyncPlay group.
struct WatchPartyLobbyView: View {
    @Bindable var model: WatchPartyModel
    var play: (PlaybackRequest) -> Void
    var changeTime: () -> Void
    var leave: () -> Void
    var close: () -> Void

    @Environment(SyncPlayManager.self) private var syncPlay
    @State private var removing: PartyPerson?
    @State private var showEnd = false

    private var party: WatchPartyState? { model.state }

    /// Changes whenever the controls on offer do, so Apple TV can put focus back on the main one.
    private var controlsKey: String {
        guard let party else { return "" }
        return "\(party.isLobby)-\(party.isWaiting)-\(party.isStarted)-\(model.isHost)-\(model.joinFailed)"
    }

    var body: some View {
        WatchPartyLobbyLayout(focusKey: controlsKey) {
            title
        } schedule: {
            if let party, let at = WatchPartyTime.upcoming(party) {
                schedule(party, at: at)
            }
        } invite: {
            if let party {
                if party.isLobby || party.isWaiting {
                    invite(party)
                } else {
                    progress(party)
                }
            }
        } rest: {
            if let party {
                people(party)
                if party.isLobby { controls(party) }
                if party.isWaiting { waitingControls }
                SyncPlayNote(groupName: party.isStarted ? party.groupName : nil)
            }
        }
        .sensoryFeedback(.success, trigger: party?.people.filter(\.ready).count ?? 0) { old, new in new > old }
        .alert("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let person = removing { Task { await model.remove(person) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They leave the watch party and can't join it again with the code.")
        }
        .alert("End This Watch Party?", isPresented: $showEnd) {
            Button("End Party", role: .destructive) {
                Task { if await model.end() { close() } }
            }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("It's called off for everyone, and the code stops working.")
        }
        // The host's group is up (or already was, for someone joining late): join it and play.
        .onChange(of: party?.groupId, initial: true) { _, _ in joinIfStarted() }
    }

    private func joinIfStarted() {
        Task {
            guard let request = await model.joinStarted(syncPlay: syncPlay) else { return }
            HapticManager.success()
            play(request)
        }
    }

    private func startWatching() {
        Task {
            guard let request = await model.startWatching(syncPlay: syncPlay) else { return }
            HapticManager.success()
            play(request)
        }
    }

    // MARK: Title

    private var title: some View {
        VStack(spacing: DT.Spacing.sm) {
            RetryingAsyncImage(url: model.posterURL, logCategory: "WatchParty") { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ZStack {
                    DT.Color.backgroundTertiary
                    Image(systemName: party?.itemType == "Episode" ? "tv" : "film")
                        .font(.system(size: 40))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
            }
            .frame(maxHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .accessibilityHidden(true)
            Text(party?.itemName ?? "")
                .font(DT.Font.sectionTitle)
                .multilineTextAlignment(.center)
            if let host = model.hostName {
                Text(model.isHost ? String(localized: "You're the host") : String(localized: "Hosted by \(host)"))
                    .font(DT.Font.callout)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    // MARK: Scheduled start

    private func schedule(_ party: WatchPartyState, at: Date) -> some View {
        VStack(spacing: DT.Spacing.xs) {
            Label("Starts \(at.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))", systemImage: "calendar")
                .font(DT.Font.callout)
                .foregroundStyle(DT.Color.textSecondary)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.countdown(to: at, now: context.date))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(DT.Color.accent)
                    .contentTransition(.numericText(countsDown: true))
            }
            Text(lobbyText(party))
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DT.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.xl))
        .accessibilityElement(children: .combine)
    }

    private func lobbyText(_ party: WatchPartyState) -> String {
        guard party.isWaiting, let opens = party.lobbyOpens else {
            return String(localized: "The lobby is open. Get ready to watch.")
        }
        let time = opens.formatted(date: .omitted, time: .shortened)
        return model.isHost
            ? String(localized: "The lobby opens at \(time). You can start early whenever you like.")
            : String(localized: "The lobby opens at \(time). You can close this and come back; Arcfin lets you know when it opens.")
    }

    static func countdown(to date: Date, now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded(.up))
        guard seconds > 0 else { return String(localized: "Any moment now") }
        let clock = Duration.seconds(seconds % 86_400).formatted(.time(pattern: .hourMinuteSecond))
        let days = seconds / 86_400
        return days > 0 ? String(localized: "\(days)d \(clock)") : clock
    }

    // MARK: Waiting for a scheduled start

    private var waitingControls: some View {
        VStack(spacing: DT.Spacing.sm) {
            if model.isHost {
                Button(action: startWatching) {
                    Label("Start Now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || model.isConnecting)
                .watchPartyPrimary()
                Button(action: changeTime) {
                    Label("Change Time", systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isBusy)
                Button(role: .destructive) { HapticManager.warning(); showEnd = true } label: {
                    Label("End Party", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isBusy)
            }
            Button(action: leave) {
                Text("Leave Watch Party")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .watchPartyPrimary(!model.isHost)
        }
        .tint(DT.Color.accent)
    }

    // MARK: Code and QR code

    @ViewBuilder private func invite(_ party: WatchPartyState) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            if party.locked {
                Label("Locked: no one new can join.", systemImage: "lock.fill")
                    .font(DT.Font.callout)
                    .foregroundStyle(DT.Color.textSecondary)
            } else {
                if let link = model.link {
                    WatchPartyQRCode(text: link.absoluteString)
                        .frame(width: 180, height: 180)
                        .padding(DT.Spacing.sm)
                        .background(.white, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                        .accessibilityLabel("QR code for this watch party")
                }
                Text(party.code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .partyTextSelection()
                    .accessibilityLabel(Text("Code \(party.code.map(String.init).joined(separator: " "))"))
                Text("Others on this server scan the QR code with the Camera app or in Arcfin, or enter the code.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DT.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.xl))
    }

    // MARK: Starting and started

    @ViewBuilder private func progress(_ party: WatchPartyState) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            if model.joinFailed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityHidden(true)
                Text("Couldn't join the host's SyncPlay group.")
                    .font(DT.Font.body)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    model.retryJoin()
                    joinIfStarted()
                }
                .buttonStyle(.borderedProminent)
                .watchPartyPrimary()
            } else if party.isStarted && model.isHost {
                Text("The watch party has started.")
                    .font(DT.Font.body)
                Button("Back to the Lobby") { Task { await model.reset() } }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                    .watchPartyPrimary()
            } else {
                ProgressView()
                Text(progressText(party))
                    .font(DT.Font.body)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                // A start that isn't going anywhere on this device (the app was closed, or
                // the host left and this person took over) can go back to the lobby.
                if model.isHost && !model.isConnecting {
                    Button("Back to the Lobby") { Task { await model.reset() } }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy)
                }
            }
        }
        .tint(DT.Color.accent)
        .padding(DT.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.xl))
    }

    private func progressText(_ party: WatchPartyState) -> String {
        if party.isStarted { return String(localized: "Joining…") }
        if model.isHost { return String(localized: "Starting SyncPlay…") }
        return String(localized: "\(model.hostName ?? String(localized: "The host")) is starting the watch party…")
    }

    // MARK: People

    private func people(_ party: WatchPartyState) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
            HStack {
                Text("Who's Here")
                    .font(DT.Font.cardTitle)
                Spacer()
                if !party.isWaiting {
                    Text("\(party.people.filter(\.ready).count) of \(party.people.count) ready")
                        .font(DT.Font.caption.monospacedDigit())
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(party.people) { person in
                    if model.isHost, !person.isMe, party.isLobby || party.isWaiting {
                        Menu {
                            Button("Remove from Watch Party", systemImage: "person.badge.minus", role: .destructive) {
                                removing = person
                            }
                        } label: {
                            PartyPersonRow(person: person, waiting: party.isWaiting, startsAt: WatchPartyTime.upcoming(party))
                        }
                        .arcfinPlainButton(cornerRadius: DT.Radius.lg, prominent: false)
                    } else {
                        PartyPersonRow(person: person, waiting: party.isWaiting, startsAt: WatchPartyTime.upcoming(party))
                            .tvFocusable(cornerRadius: DT.Radius.lg)
                    }
                    if person.id != party.people.last?.id {
                        Divider().padding(.leading, DT.Spacing.md)
                    }
                }
            }
            .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
            if party.people.count == 1 {
                Text(model.isHost ? "Waiting for others to join. You can also start on your own."
                                  : "Waiting for others to join.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    // MARK: Controls

    @ViewBuilder private func controls(_ party: WatchPartyState) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            if model.isHost {
                Button(action: startWatching) {
                    Label("Start Watching", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || model.isConnecting)
                .watchPartyPrimary()
                if model.others.contains(where: { !$0.ready }) {
                    Text("Not everyone is ready yet. You can start anyway.")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Toggle(isOn: Binding(get: { party.locked }, set: { locked in Task { await model.setLocked(locked) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock the Party")
                        Text("No one new can join, even with the code.")
                            .font(DT.Font.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .padding(DT.Spacing.md)
                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .disabled(model.isBusy)
            } else if let me = party.me {
                Toggle(isOn: Binding(get: { me.ready }, set: { ready in Task { await model.setReady(ready) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I'm Ready")
                        Text("\(model.hostName ?? String(localized: "The host")) starts the party when everyone's ready.")
                            .font(DT.Font.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .padding(DT.Spacing.md)
                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .disabled(model.isBusy)
                .watchPartyPrimary()
            }
        }
        .tint(DT.Color.accent)
    }
}

/// For people watching from another app: the party is a SyncPlay group they can join there.
private struct SyncPlayNote: View {
    let groupName: String?

    @State private var isExpanded = false

    private var text: String {
        let join = groupName.map { String(localized: "once the party starts, join the SyncPlay group named \"\($0)\".") }
            ?? String(localized: "once the party starts, join its SyncPlay group. Its name appears here when the host starts.")
        return String(localized: "Watch parties use Jellyfin's SyncPlay. Arcfin gives the best experience, but anyone can join from another app that supports SyncPlay: \(join) The host has to start the party in Arcfin.")
    }

    var body: some View {
        WatchPartyDisclosure(isExpanded: $isExpanded) {
            Text(text)
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textSecondary)
                .partyTextSelection()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DT.Spacing.xs)
        } label: {
            Label("Watching from another app?", systemImage: "questionmark.circle")
                .font(DT.Font.callout)
                .foregroundStyle(DT.Color.textPrimary)
        }
        .tint(DT.Color.accent)
        .padding(DT.Spacing.md)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
    }
}

private struct PartyPersonRow: View {
    let person: PartyPerson
    /// Before the lobby opens nobody can be ready yet, only in.
    var waiting = false
    /// A scheduled start, shown in the person's own time when they're in another zone.
    var startsAt: Date?

    private var localStart: String? {
        guard let startsAt, let zone = PartyClock.zone(of: person, at: startsAt) else { return nil }
        return String(localized: "\(PartyClock.time(startsAt, in: zone)) there (\(PartyClock.city(zone)))")
    }

    private var name: String { person.isMe ? String(localized: "You") : person.name }

    private var status: String {
        if waiting { return String(localized: "Joined") }
        if person.isAway { return String(localized: "Away") }
        return person.ready ? String(localized: "Ready") : String(localized: "Not Ready")
    }

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            Circle()
                .fill(person.isAway ? DT.Color.textSecondary : DT.Color.accent)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DT.Spacing.xxs) {
                    Text(name)
                        .font(DT.Font.body)
                        .foregroundStyle(DT.Color.textPrimary)
                    if person.isHost {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(DT.Color.accent)
                            .accessibilityHidden(true)
                    }
                }
                if !person.deviceName.isEmpty {
                    Text(person.deviceName)
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                if let localStart {
                    Label(localStart, systemImage: "globe")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            Spacer()
            Label(status, systemImage: waiting ? "person.crop.circle.badge.checkmark"
                  : person.isAway ? "moon.zzz" : (person.ready ? "checkmark.circle.fill" : "circle"))
                .font(DT.Font.caption)
                .foregroundStyle(person.ready && !person.isAway && !waiting ? DT.Color.accent : DT.Color.textSecondary)
        }
        .padding(.horizontal, DT.Spacing.md)
        .padding(.vertical, DT.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.isHost ? Text("\(name), host, \(status)") : Text("\(name), \(status)"))
        .accessibilityValue(localStart ?? "")
    }
}

/// The lobby as one column, top to bottom: on iPhone, iPad and the Mac.
struct StackedWatchPartyLobby<Heading: View, Schedule: View, Invite: View, Rest: View>: View {
    var focusKey: String
    @ViewBuilder var heading: Heading
    @ViewBuilder var schedule: Schedule
    @ViewBuilder var invite: Invite
    @ViewBuilder var rest: Rest

    var body: some View {
        ScrollView {
            VStack(spacing: DT.Spacing.lg) {
                heading
                schedule
                invite
                rest
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.vertical, DT.Spacing.lg)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}
