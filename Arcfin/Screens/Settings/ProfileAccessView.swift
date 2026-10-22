// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// The signed-in profile as the server sees it: account details, parental controls, what
/// it's allowed to do, and the playback preferences saved on the server. Read-only — these
/// are changed by an administrator in the server's dashboard.
struct ProfileAccessView: View {
    @Environment(AuthManager.self) private var authManager
    private var rules: ProfileRules { .shared }

    var body: some View {
        List {
            if let profile = rules.profile {
                accountSection(profile)
                parentalSection(profile.policy)
                permissionsSection(profile.policy)
                preferencesSection(profile)
            } else {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Your Profile")
        .refreshable { await reload() }
        .task { if rules.profile == nil { await reload() } }
    }

    private func reload() async {
        guard let credential = authManager.state.credential else { return }
        await rules.load(credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken))
    }

    // MARK: - Sections

    private func accountSection(_ profile: UserProfileDetails) -> some View {
        Section {
            LabeledContent("Name", value: profile.name)
            if let server = profile.serverName { LabeledContent("Server", value: server) }
            LabeledContent("Role", value: profile.policy.isAdministrator ? "Administrator" : "User")
            LabeledContent("Password", value: profile.hasPassword ? "Set" : "None")
            if let date = profile.lastLoginDate {
                LabeledContent("Last Sign-In", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let date = profile.lastActivityDate {
                LabeledContent("Last Active", value: date.formatted(.relative(presentation: .named)))
            }
        } header: {
            Text("Account")
        }
    }

    private func parentalSection(_ policy: UserPolicy) -> some View {
        Section {
            LabeledContent("Maximum Rating", value: maxRatingText(policy))
            LabeledContent("Unrated Titles", value: unratedText(policy))
            if !policy.allowedTags.isEmpty {
                LabeledContent("Only Tagged", value: policy.allowedTags.joined(separator: ", "))
            }
            if !policy.blockedTags.isEmpty {
                LabeledContent("Hidden Tags", value: policy.blockedTags.joined(separator: ", "))
            }
            if policy.accessSchedules.isEmpty {
                LabeledContent("Allowed Times", value: "Any time")
            } else {
                ForEach(Array(policy.accessSchedules.enumerated()), id: \.offset) { index, schedule in
                    LabeledContent(index == 0 ? "Allowed Times" : "", value: ProfileRules.describe(schedule))
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
            permission("Video Transcoding", policy.enableVideoPlaybackTranscoding)
            permission("Audio Transcoding", policy.enableAudioPlaybackTranscoding)
            permission("Remuxing", policy.enablePlaybackRemuxing)
            permission("Manage Collections", policy.isAdministrator || policy.enableCollectionManagement)
            permission("Delete Media", policy.isAdministrator || policy.enableContentDeletion)
            if let limit = policy.remoteClientBitrateLimit, limit > 0 {
                LabeledContent("Remote Quality Limit", value: "\(limit / 1_000_000) Mb/s")
            }
            if policy.maxActiveSessions > 0 {
                LabeledContent("Simultaneous Streams", value: "\(policy.maxActiveSessions)")
            }
        } header: {
            Text("Permissions")
        }
    }

    private func preferencesSection(_ profile: UserProfileDetails) -> some View {
        Section {
            LabeledContent("Audio Language", value: languageName(profile.audioLanguagePreference) ?? "Default")
            LabeledContent("Subtitle Language", value: languageName(profile.subtitleLanguagePreference) ?? "Default")
            if let mode = profile.subtitleMode { LabeledContent("Subtitles", value: subtitleModeText(mode)) }
            permission("Play Next Episode Automatically", profile.enableNextEpisodeAutoPlay)
            permission("Remember Audio Choices", profile.rememberAudioSelections)
            permission("Remember Subtitle Choices", profile.rememberSubtitleSelections)
        } header: {
            Text("Saved on the Server")
        } footer: {
            Text("Change these, and the limits above, from the server's dashboard.")
        }
    }

    // MARK: - Helpers

    private func permission(_ title: String, _ allowed: Bool, detail: String? = nil) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if let detail { Text(detail).foregroundStyle(DT.Color.textSecondary) }
                Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(allowed ? Color.green : DT.Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(allowed ? "Allowed" : "Not allowed")
    }

    private func maxRatingText(_ policy: UserPolicy) -> String {
        guard policy.maxParentalRating != nil else { return "None" }
        return rules.maxRatingName ?? "Set"
    }

    private func unratedText(_ policy: UserPolicy) -> String {
        guard !policy.blockUnratedItems.isEmpty else { return "Shown" }
        let names: [String: String] = [
            "Movie": "Movies", "Series": "Shows", "Trailer": "Trailers", "Book": "Books",
            "Music": "Music", "LiveTvChannel": "Live TV", "LiveTvProgram": "Live TV",
            "ChannelContent": "Channels",
        ]
        let hidden = Array(Set(policy.blockUnratedItems.compactMap { names[$0] ?? $0 })).sorted()
        return "Hidden: " + hidden.joined(separator: ", ")
    }

    private func subtitleModeText(_ mode: String) -> String {
        switch mode {
        case "Always": "Always on"
        case "OnlyForced": "Forced only"
        case "None": "Off"
        case "Smart": "Smart"
        default: "Default"
        }
    }

    private func languageName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
