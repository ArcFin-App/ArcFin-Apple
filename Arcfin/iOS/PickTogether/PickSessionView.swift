// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

struct PickSessionView: View {
    @Bindable var model: PickTogetherModel
    var showMatches: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(SyncPlayManager.self) private var syncPlay
    @Environment(\.dismiss) private var dismiss
    @State private var showInvite = false
    @State private var removing: PickPerson?
    @State private var likes = 0
    @State private var skips = 0

    var body: some View {
        VStack(spacing: DT.Spacing.sm) {
            header
            GeometryReader { proxy in
                // Every card the same 2:3 size, whatever shape the poster is: the biggest that
                // fits this screen (an iPhone SE's as much as a 13-inch iPad's), with room for the
                // cards stacked behind, and no wider than reads well on the biggest iPad.
                let width = max(0, min(proxy.size.width, (proxy.size.height - 24) * 2 / 3, 760))
                ZStack {
                    if model.cards.isEmpty {
                        finished
                    } else {
                        ForEach(Array(model.cards.prefix(3).enumerated().reversed()), id: \.element.id) { index, card in
                            PickCardView(card: card, posterURL: PickPoster.url(card, authManager), isTop: index == 0,
                                         size: CGSize(width: width, height: width * 1.5)) { like in
                                decide(card, like: like)
                            }
                            .scaleEffect(1 - CGFloat(index) * 0.04)
                            .offset(y: CGFloat(index) * 10)
                            .allowsHitTesting(index == 0)
                            .accessibilityHidden(index != 0)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            if let top = model.cards.first {
                buttons(for: top)
            }
        }
        .padding(.bottom, DT.Spacing.md)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: showMatches) {
                    Label("Matches", systemImage: "heart.circle")
                }
                .badge(model.state?.matches.count ?? 0)
                .disabled(model.state?.matches.isEmpty ?? true)
            }
        }
        .overlay {
            if showInvite, let link = model.joinLink, let code = model.state?.code {
                PickInvitePanel(link: link, code: code) { showInvite = false }
                    .transition(.opacity)
            }
        }
        .overlay {
            if let match = model.newMatch {
                PickMatchPanel(match: match, posterURL: PickPoster.url(match.item, authManager),
                               together: model.state?.together.flatMap { $0.itemId == match.item.id ? $0 : nil },
                               canWatchTogether: ProfileRules.shared.canUseSyncPlay && !model.others.isEmpty,
                               watchHere: { watchHere(match.item) }, watchOn: { watch(match.item, on: $0) },
                               watchTogether: { Task { await model.watchTogether(match.item) } },
                               notTogether: { Task { await model.notTogether() } },
                               details: { open(match.item) }, keepGoing: { model.dismissMatch() })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(DT.Animation.standard, value: showInvite)
        .animation(DT.Animation.standard, value: model.newMatch)
        // Firm taps, so a swipe is felt: heavier for "want to watch" than for skip.
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: likes)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: skips)
        .sensoryFeedback(.success, trigger: model.state?.matches.count ?? 0)
        .onAppear { if model.others.isEmpty, model.isHost { showInvite = true } }
        .alert("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let person = removing { Task { await model.remove(person) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They leave the session and can't join it again with the code.")
        }
        // Everyone's in for watching together: set up or join SyncPlay, then open the player.
        .onChange(of: model.state?.together) { _, _ in
            Task {
                guard let target = await model.advanceTogether(syncPlay: syncPlay) else { return }
                model.newMatch = nil
                dismiss()
                try? await Task.sleep(for: .seconds(0.4))
                WatchRoute.open(id: target.id, startTicks: target.startTicks)
            }
        }
    }

    // MARK: Header: code, invite and who's here

    private var header: some View {
        VStack(spacing: DT.Spacing.xs) {
            HStack(spacing: DT.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Code")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                    Text(model.state?.code ?? "")
                        .font(.system(.title2, design: .monospaced, weight: .bold))
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                if model.isHost {
                    Button {
                        Task { await model.setLocked(!(model.state?.locked ?? false)) }
                    } label: {
                        Image(systemName: model.state?.locked == true ? "lock.fill" : "lock.open")
                    }
                    .buttonStyle(.bordered)
                    .tint(DT.Color.accent)
                    .accessibilityLabel(model.state?.locked == true ? "Unlock Session" : "Lock Session")
                    .accessibilityHint("A locked session takes no one new, even with the code")
                }
                Button { showInvite = true } label: {
                    Label("Invite", systemImage: "qrcode")
                }
                .buttonStyle(.bordered)
                .tint(DT.Color.accent)
                .disabled(model.state?.locked == true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Spacing.xs) {
                    ForEach(model.state?.people ?? []) { person in
                        if model.isHost, !person.isMe {
                            Menu {
                                Button("Remove from Session", systemImage: "person.badge.minus", role: .destructive) {
                                    removing = person
                                }
                            } label: {
                                PersonChip(person: person)
                            }
                            .buttonStyle(.plain)
                        } else {
                            PersonChip(person: person)
                        }
                    }
                }
            }
            if model.state?.locked == true {
                Label("Locked: no one new can join.", systemImage: "lock.fill")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.others.isEmpty {
                Text("Invite someone to start matching. You can start swiping now.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .frame(maxWidth: 800)
    }

    private func buttons(for card: PickCard) -> some View {
        HStack(spacing: DT.Spacing.xl) {
            Button { decide(card, like: false) } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.bold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Skip")
            Button { decide(card, like: true) } label: {
                Image(systemName: "heart.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DT.Color.onAccent)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(DT.Color.accent).interactive(), in: .circle)
            .accessibilityLabel("Want to Watch")
        }
    }

    private var finishedMessage: String {
        if model.others.contains(where: { $0.swiped < $0.total }) {
            return String(localized: "Waiting for the others to finish. A match shows up here as soon as there is one.")
        }
        if model.isHost {
            return String(localized: "No match this round. Deal new titles to keep going: nobody sees any of these again.")
        }
        return String(localized: "No match this round. \(model.hostName ?? String(localized: "The person who started the session")) can deal new titles.")
    }

    private func decide(_ card: PickCard, like: Bool) {
        if like { likes += 1 } else { skips += 1 }
        model.swipe(card, like: like)
    }

    private var finished: some View {
        VStack(spacing: DT.Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(DT.Color.accent)
                .accessibilityHidden(true)
            Text("You've Seen Them All")
                .font(DT.Font.sectionTitle)
            Text(finishedMessage)
                .font(DT.Font.body)
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
            if model.isHost {
                Button {
                    Task { await model.restart() }
                } label: {
                    Label("Deal New Titles", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(DT.Color.accent)
                .disabled(model.isBusy)
            }
        }
        .padding(DT.Spacing.lg)
    }

    /// Plays it here: a movie from where it was left, a show from its next episode.
    private func watchHere(_ card: PickCard) {
        model.newMatch = nil
        dismiss()
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            WatchRoute.open(id: card.id)
        }
    }

    /// Plays it on another device signed in to the server, the same way Play On does.
    private func watch(_ card: PickCard, on session: JellyfinSession) {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        model.newMatch = nil
        Task {
            guard let request = await WatchRoute.resolve(id: card.id, credential: credential, authHeader: header) else { return }
            AppServices.remoteSessions.play(request.item, on: session)
        }
    }

    /// Opens the title's page, with its episodes, trailer and SharePlay.
    private func open(_ card: PickCard) {
        model.newMatch = nil
        dismiss()
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            ArcfinRouting.openItem(id: card.id)
        }
    }
}

enum PickPoster {
    @MainActor
    static func url(_ card: PickCard, _ authManager: AuthManager) -> URL? {
        guard let credential = authManager.state.credential else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: card.id, tag: "", type: .primary,
                                            fillWidth: 700, token: credential.accessToken)
    }
}

private struct PersonChip: View {
    let person: PickPerson

    private var name: String { person.isMe ? String(localized: "You") : person.name }

    var body: some View {
        HStack(spacing: DT.Spacing.xxs) {
            Circle()
                .fill(person.isAway ? DT.Color.textSecondary : DT.Color.accent)
                .frame(width: 8, height: 8)
            if person.isHost {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityHidden(true)
            }
            Text(name)
                .font(DT.Font.caption)
            Text("\(min(person.swiped, person.total))/\(person.total)")
                .font(DT.Font.caption2.monospacedDigit())
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, DT.Spacing.sm)
        .padding(.vertical, DT.Spacing.xxs + 2)
        .background(DT.Color.backgroundTertiary, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.isAway ? Text("\(name), away") : Text("\(name), \(person.swiped) of \(person.total) swiped"))
    }
}

// MARK: - Card

struct PickCardView: View {
    let card: PickCard
    let posterURL: URL?
    let isTop: Bool
    let size: CGSize
    var decide: (Bool) -> Void

    @State private var drag: CGSize = .zero
    /// Past the point where letting go counts, for a tap that says so.
    @State private var committed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let threshold: CGFloat = 110

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RetryingAsyncImage(url: posterURL, logCategory: "PickTogether") { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    DT.Color.backgroundTertiary
                    Image(systemName: card.isShow ? "tv" : "film")
                        .font(.system(size: 44))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: DT.Spacing.xxs) {
                Text(card.name)
                    .font(DT.Font.sectionTitle)
                    .lineLimit(2)
                Text(details)
                    .font(DT.Font.caption)
                    .opacity(0.85)
                if !card.overview.isEmpty {
                    Text(card.overview)
                        .font(DT.Font.callout)
                        .lineLimit(3)
                        .opacity(0.85)
                        .padding(.top, 2)
                }
            }
            .foregroundStyle(.white)
            .padding(DT.Spacing.md)

            stamp
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: committed) { _, new in new }
        .offset(x: drag.width, y: drag.height * 0.3)
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width / 22)))
        .gesture(isTop ? swipe : nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe right if you'd watch it, left to skip")
        .accessibilityAction(named: "Want to Watch") { decide(true) }
        .accessibilityAction(named: "Skip") { decide(false) }
    }

    private var details: String {
        var parts: [String] = []
        parts.append(card.isShow ? String(localized: "Show") : String(localized: "Movie"))
        if let year = card.year { parts.append(String(year)) }
        if let rating = card.rating, rating > 0 { parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        if let minutes = card.runtimeMinutes, !card.isShow {
            parts.append(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        }
        if let official = card.officialRating { parts.append(official) }
        parts.append(contentsOf: card.genres.prefix(2))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var stamp: some View {
        let progress = min(abs(drag.width) / threshold, 1)
        if drag.width != 0 {
            Text(drag.width > 0 ? "WATCH" : "SKIP")
                .font(.system(.title, design: .rounded, weight: .heavy))
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.xxs)
                .foregroundStyle(drag.width > 0 ? DT.Color.accent : .white)
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.sm).stroke(drag.width > 0 ? DT.Color.accent : .white, lineWidth: 3))
                .rotationEffect(.degrees(drag.width > 0 ? -12 : 12))
                .opacity(progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: drag.width > 0 ? .topLeading : .topTrailing)
                .padding(DT.Spacing.lg)
                .accessibilityHidden(true)
        }
    }

    private var swipe: some Gesture {
        DragGesture()
            .onChanged {
                drag = $0.translation
                committed = abs($0.translation.width) > threshold
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width
                if abs(value.translation.width) > threshold || abs(predicted) > threshold * 2.5 {
                    let like = (abs(value.translation.width) > threshold ? value.translation.width : predicted) > 0
                    withAnimation(DT.Animation.fast) { drag.width = like ? 900 : -900 }
                    Task {
                        try? await Task.sleep(for: .seconds(0.18))
                        decide(like)
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { drag = .zero }
                }
                committed = false
            }
    }
}

// MARK: - Invite and match panels

/// The session's QR code and code, over the cards: others scan it with the Camera app or
/// Pick Together's scanner, or type the code.
private struct PickInvitePanel: View {
    let link: URL
    let code: String
    var close: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55)).ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            VStack(spacing: DT.Spacing.md) {
                Text("Invite Others")
                    .font(DT.Font.sectionTitle)
                QRCodeImage(text: link.absoluteString)
                    .frame(width: 220, height: 220)
                    .padding(DT.Spacing.sm)
                    .background(.white, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                    .accessibilityLabel("QR code for this session")
                Text(code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text("Code \(code.map(String.init).joined(separator: " "))"))
                Text("Scan this with the Camera app or in Pick Together, or enter the code. Everyone needs to be signed in to this server.")
                    .font(DT.Font.callout)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Done", action: close)
                    .buttonStyle(.borderedProminent)
                    .tint(DT.Color.accent)
            }
            .padding(DT.Spacing.lg)
            .frame(maxWidth: 400)
            .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.sheet))
            .padding(DT.Spacing.pagePad)
        }
    }
}

private struct PickMatchPanel: View {
    let match: PickMatch
    let posterURL: URL?
    let together: PickTogetherPlan?
    let canWatchTogether: Bool
    var watchHere: () -> Void
    var watchOn: (JellyfinSession) -> Void
    var watchTogether: () -> Void
    var notTogether: () -> Void
    var details: () -> Void
    var keepGoing: () -> Void

    private var remote: RemoteSessions { AppServices.remoteSessions }

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.opacity(0.96).ignoresSafeArea()
            VStack(spacing: DT.Spacing.lg) {
                Text("It's a Match")
                    .font(DT.Font.hero)
                    .foregroundStyle(DT.Color.accent)
                RetryingAsyncImage(url: posterURL, logCategory: "PickTogether") { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    DT.Color.backgroundTertiary
                }
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .frame(maxHeight: 380)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl))
                .accessibilityHidden(true)
                Text(match.item.name)
                    .font(DT.Font.sectionTitle)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(DT.Font.body)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                if let together, together.iAmIn {
                    VStack(spacing: DT.Spacing.sm) {
                        ProgressView()
                        Button("Don't Watch Together", action: notTogether)
                            .buttonStyle(.bordered)
                            .tint(DT.Color.accent)
                            .disabled(together.groupId != nil)
                    }
                } else {
                VStack(spacing: DT.Spacing.sm) {
                    if canWatchTogether {
                        Button(action: watchTogether) {
                            Label(together == nil ? "Watch Together" : "Join Watch Together", systemImage: "person.2.wave.2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    Button(action: watchHere) {
                        Label("Watch Here", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(canWatchTogether ? AnyPrimitiveButtonStyle(.bordered) : AnyPrimitiveButtonStyle(.borderedProminent))
                    .controlSize(.large)
                    if !remote.sessions.isEmpty {
                        Menu {
                            ForEach(remote.sessions) { session in
                                Button(session.deviceName) { watchOn(session) }
                            }
                        } label: {
                            Label("Watch On", systemImage: "av.remote")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    Button(action: details) {
                        Text("See Details")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Button(action: keepGoing) {
                        Text("Keep Swiping")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .tint(DT.Color.accent)
                .frame(maxWidth: 360)
                }
            }
            .padding(DT.Spacing.pagePad)
        }
        // The devices online right now, for Watch On.
        .task { await remote.refresh() }
    }

    private var subtitle: String {
        guard let together else { return String(localized: "You all want to watch this one.") }
        if together.groupId != nil { return String(localized: "Starting SyncPlay…") }
        if together.iAmIn {
            return together.waiting.isEmpty
                ? String(localized: "Everyone's in. Starting SyncPlay…")
                : String(localized: "Waiting for \(together.waiting.formatted(.list(type: .and))) to say yes.")
        }
        return String(localized: "Someone wants to watch this together, in sync on each of your devices.")
    }
}

/// Lets one button switch between two primitive button styles.
private struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - Matches

struct PickMatchesList: View {
    @Bindable var model: PickTogetherModel
    var open: (PickCard) -> Void
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        List(model.state?.matches.reversed() ?? []) { match in
            Button { open(match.item) } label: {
                HStack(spacing: DT.Spacing.sm) {
                    RetryingAsyncImage(url: PickPoster.url(match.item, authManager), logCategory: "PickTogether") { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        DT.Color.backgroundTertiary
                    }
                    .frame(width: 48, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.item.name)
                            .font(DT.Font.cardTitle)
                            .foregroundStyle(DT.Color.textPrimary)
                        if let year = match.item.year {
                            Text(String(year))
                                .font(DT.Font.caption)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Matches")
        .navigationBarTitleDisplayMode(.inline)
    }
}
