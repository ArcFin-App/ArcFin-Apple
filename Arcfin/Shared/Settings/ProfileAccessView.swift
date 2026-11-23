// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// The signed-in profile as the server sees it: account details, the libraries it can see,
/// parental controls, what it's allowed to do, and the playback preferences saved on the
/// server. Read-only — these are changed by an administrator in the server's dashboard.
struct ProfileAccessView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    private var rules: ProfileRules { .shared }

    var body: some View {
        SettingsForm {
            if let credential = authManager.state.credential {
                identitySection(credential)
            }
            if let profile = rules.profile {
                accountSection(profile)
                librariesSection(profile.policy)
                parentalSection(profile.policy)
                permissionsSection(profile.policy)
                preferencesSection(profile)
            } else {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .tvReadOnlyRow()
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(String(localized: "Your Profile"))
        .refreshable { await reload() }
        .task { if rules.profile == nil { await reload() } }
    }

    private func reload() async {
        guard let credential = authManager.state.credential else { return }
        await rules.load(credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken))
    }

    // MARK: - Sections

    private func identitySection(_ credential: ServerCredential) -> some View {
        Section {
            HStack(spacing: 16) {
                ProfileAvatar(profile: credential, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(credential.displayName)
                        .font(.headline)
                        .foregroundStyle(DT.Color.textPrimary)
                    Text(credential.baseURL.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .tvReadOnlyRow()
        }
    }

    private func accountSection(_ profile: UserProfileDetails) -> some View {
        Section {
            LabeledContent("Name", value: profile.name).tvReadOnlyRow()
            if let server = profile.serverName { LabeledContent("Server", value: server).tvReadOnlyRow() }
            LabeledContent("Role", value: profile.policy.isAdministrator ? String(localized: "Administrator") : String(localized: "User")).tvReadOnlyRow()
            LabeledContent("Password", value: profile.hasPassword ? String(localized: "Set") : String(localized: "None")).tvReadOnlyRow()
            if let date = profile.lastLoginDate {
                LabeledContent("Last Sign-In", value: date.formatted(date: .abbreviated, time: .shortened)).tvReadOnlyRow()
            }
            if let date = profile.lastActivityDate {
                LabeledContent("Last Active", value: date.formatted(.relative(presentation: .named))).tvReadOnlyRow()
            }
        } header: {
            Text("Account")
        }
    }

    private func librariesSection(_ policy: UserPolicy) -> some View {
        Section {
            if policy.enableAllFolders {
                LabeledContent("Libraries", value: String(localized: "All libraries")).tvReadOnlyRow()
            } else {
                let visible = mediaRepo.libraries.filter { policy.enabledFolders.contains($0.id) }
                if visible.isEmpty {
                    LabeledContent("Libraries", value: String(localized: "None")).tvReadOnlyRow()
                } else {
                    ForEach(visible) { library in
                        Text(library.name).tvReadOnlyRow()
                    }
                }
            }
        } header: {
            Text("Libraries")
        }
    }

    private func parentalSection(_ policy: UserPolicy) -> some View {
        Section {
            LabeledContent("Maximum Rating", value: maxRatingText(policy)).tvReadOnlyRow()
            LabeledContent("Unrated Titles", value: unratedText(policy)).tvReadOnlyRow()
            if !policy.allowedTags.isEmpty {
                LabeledContent("Only Tagged", value: policy.allowedTags.joined(separator: ", ")).tvReadOnlyRow()
            }
            if !policy.blockedTags.isEmpty {
                LabeledContent("Hidden Tags", value: policy.blockedTags.joined(separator: ", ")).tvReadOnlyRow()
            }
            if policy.accessSchedules.isEmpty {
                LabeledContent("Allowed Times", value: String(localized: "Any time")).tvReadOnlyRow()
            } else {
                ForEach(Array(policy.accessSchedules.enumerated()), id: \.offset) { index, schedule in
                    LabeledContent(index == 0 ? "Allowed Times" : "", value: ProfileRules.describe(schedule)).tvReadOnlyRow()
                }
            }
        } header: {
            Text("Parental Controls")
        } footer: {
            Text(policy.restrictsContent
                 ? "Titles outside these limits are hidden everywhere in Arcfin, including Discover and requests."
                 : "No content limits are set for this profile.")
        }
    }

    private func permissionsSection(_ policy: UserPolicy) -> some View {
        Section {
            permission("Play Media", policy.enableMediaPlayback)
            permission("Download", policy.enableContentDownloading)
            permission("Search for Subtitles", policy.isAdministrator || policy.enableSubtitleManagement)
            permission("Watch Together (SyncPlay)", policy.syncPlayAccess != "None",
                       detail: policy.syncPlayAccess == "JoinGroups" ? "Join only" : nil)
            permission("Remote Access", policy.enableRemoteAccess)
            permission("Live TV", policy.enableLiveTvAccess)
            permission("Record Live TV", policy.enableLiveTvAccess && policy.enableLiveTvManagement)
            permission("Video Transcoding", policy.enableVideoPlaybackTranscoding)
            permission("Audio Transcoding", policy.enableAudioPlaybackTranscoding)
            permission("Remuxing", policy.enablePlaybackRemuxing)
            permission("Always Transcode Remote Streams", policy.forceRemoteSourceTranscoding)
            permission("Public Sharing", policy.enablePublicSharing)
            permission("Manage Collections", policy.isAdministrator || policy.enableCollectionManagement)
            permission("Delete Media", policy.isAdministrator || policy.enableContentDeletion)
            if let limit = policy.remoteClientBitrateLimit, limit > 0 {
                LabeledContent("Remote Quality Limit", value: String(localized: "\(limit / 1_000_000) Mb/s")).tvReadOnlyRow()
            }
            if policy.maxActiveSessions > 0 {
                LabeledContent("Simultaneous Streams", value: policy.maxActiveSessions.formatted()).tvReadOnlyRow()
            }
        } header: {
            Text("Permissions")
        }
    }

    private func preferencesSection(_ profile: UserProfileDetails) -> some View {
        Section {
            LabeledContent("Audio Language", value: languageName(profile.audioLanguagePreference) ?? String(localized: "Default")).tvReadOnlyRow()
            permission("Play the Default Audio Track", profile.playDefaultAudioTrack)
            LabeledContent("Subtitle Language", value: languageName(profile.subtitleLanguagePreference) ?? String(localized: "Default")).tvReadOnlyRow()
            if let mode = profile.subtitleMode { LabeledContent("Subtitles", value: subtitleModeText(mode)).tvReadOnlyRow() }
            permission("Play Next Episode Automatically", profile.enableNextEpisodeAutoPlay)
            permission("Remember Audio Choices", profile.rememberAudioSelections)
            permission("Remember Subtitle Choices", profile.rememberSubtitleSelections)
            permission("Hide Watched Titles in Latest", profile.hidePlayedInLatest)
        } header: {
            Text("Saved on the Server")
        } footer: {
            Text("Change these, and the limits above, from the server's dashboard.")
        }
    }

    // MARK: - Helpers

    private func permission(_ title: LocalizedStringKey, _ allowed: Bool, detail: LocalizedStringKey? = nil) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if let detail { Text(detail).foregroundStyle(DT.Color.textSecondary) }
                Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(allowed ? DT.Color.palette("10B981") : DT.Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(allowed ? Text("Allowed") : Text("Not allowed"))
        .tvReadOnlyRow()
    }

    private func maxRatingText(_ policy: UserPolicy) -> String {
        guard policy.maxParentalRating != nil else { return String(localized: "None") }
        return rules.maxRatingName ?? String(localized: "Set")
    }

    private func unratedText(_ policy: UserPolicy) -> String {
        guard !policy.blockUnratedItems.isEmpty else { return String(localized: "Shown") }
        let names: [String: String] = [
            "Movie": String(localized: "Movies"), "Series": String(localized: "Shows"),
            "Trailer": String(localized: "Trailers"), "Book": String(localized: "Books"),
            "Music": String(localized: "Music"), "LiveTvChannel": String(localized: "Live TV"),
            "LiveTvProgram": String(localized: "Live TV"), "ChannelContent": String(localized: "Channels"),
        ]
        let hidden = Array(Set(policy.blockUnratedItems.compactMap { names[$0] ?? $0 })).sorted()
        return String(localized: "Hidden: \(hidden.formatted(.list(type: .and)))")
    }

    private func subtitleModeText(_ mode: String) -> String {
        switch mode {
        case "Always": String(localized: "Always on")
        case "OnlyForced": String(localized: "Forced only")
        case "None": String(localized: "Off")
        case "Smart": String(localized: "Smart")
        default: String(localized: "Default")
        }
    }

    private func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
