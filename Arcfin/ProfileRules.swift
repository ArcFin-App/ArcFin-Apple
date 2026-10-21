// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import AuthCore
import JellyfinAPI
import SeerrAPI

/// The signed-in profile's parental controls and permissions, as set on the Jellyfin server.
///
/// The server applies its content rules (maximum rating, unrated items, tags) to everything
/// it returns, so the library, search, shelves and widgets are already filtered. This applies
/// the same rules to what comes from elsewhere — Seerr's catalogue, which carries no
/// Jellyfin ratings — and lets the app hide what the profile isn't allowed to use.
@Observable
@MainActor
final class ProfileRules {
    static let shared = ProfileRules()

    private(set) var profile: UserProfileDetails?
    /// The server's rating scale, e.g. "PG-13" → 13.
    private(set) var ratings: [ParentalRating] = []

    /// Seerr titles' ratings already looked up, by "movie:123" / "tv:456"; nil when TMDB has none.
    @ObservationIgnored private var certifications: [String: String?] = [:]

    var policy: UserPolicy { profile?.policy ?? UserPolicy() }
    var restrictsContent: Bool { policy.restrictsContent }
    var canDownload: Bool { policy.enableContentDownloading }
    var canManageSubtitles: Bool { policy.isAdministrator || policy.enableSubtitleManagement }
    var canUseSyncPlay: Bool { policy.syncPlayAccess != "None" }

    func load(credential: ServerCredential, authHeader: String) async {
        let client = JellyfinMediaClient()
        async let fetchedProfile = try? client.getUserProfile(credential: credential, authHeader: authHeader)
        async let fetchedRatings = try? client.getParentalRatings(credential: credential, authHeader: authHeader)
        let (newProfile, newRatings) = await (fetchedProfile, fetchedRatings)
        // A failed fetch keeps the previous profile's rules rather than dropping them, so a
        // restricted profile never briefly sees everything over a flaky connection.
        if let newProfile {
            if newProfile.policy != profile?.policy { certifications = [:] }
            profile = newProfile
        }
        if let newRatings, !newRatings.isEmpty { ratings = newRatings }
    }

    func clear() {
        profile = nil
        certifications = [:]
    }

    // MARK: - Ratings

    /// The score for a rating name. Ratings arrive in a few spellings ("PG-13", "US-PG-13",
    /// "pg13"), so names are compared loosely.
    func score(for rating: String?) -> Int? {
        guard let rating, !rating.isEmpty else { return nil }
        let wanted = Self.normalized(rating)
        if let match = ratings.first(where: { Self.normalized($0.name) == wanted }) { return match.score }
        // "US-PG-13" → "PG-13"
        if let dash = rating.firstIndex(of: "-"), rating[..<dash].count == 2 {
            let bare = Self.normalized(String(rating[rating.index(after: dash)...]))
            return ratings.first { Self.normalized($0.name) == bare }?.score
        }
        return nil
    }

    /// The name of the highest rating the profile may watch, e.g. "PG-13".
    var maxRatingName: String? {
        guard let max = policy.maxParentalRating else { return nil }
        let atMost = ratings.filter { ($0.score ?? .max) <= max }
        return atMost.max { ($0.score ?? 0) < ($1.score ?? 0) }?.name
    }

    /// Jellyfin's own rule: above the maximum is hidden; no recognised rating is hidden only
    /// when the profile blocks unrated items of that kind ("Movie", "Series").
    func allows(rating: String?, kind: String) -> Bool {
        guard let score = score(for: rating) else { return !policy.blockUnratedItems.contains(kind) }
        guard let max = policy.maxParentalRating else { return true }
        return score <= max
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Seerr

    /// Keeps only the Seerr titles this profile may see. Allowed tags can't match anything
    /// outside the library, so a profile limited to tagged media sees none of Seerr's
    /// catalogue, the same as an untagged title in the library.
    func visible(_ items: [SeerrItem], lookUp: @escaping @Sendable (SeerrItem, String) async -> String?) async -> [SeerrItem] {
        guard restrictsContent else { return items }
        guard policy.allowedTags.isEmpty else { return [] }
        let candidates = items.filter { !$0.isAdult }
        let region = Locale.current.region?.identifier ?? "US"

        let missing = candidates.filter { certifications[key($0)] == nil }
        if !missing.isEmpty {
            // A handful at a time: each is a detail request to the Seerr server.
            var index = 0
            while index < missing.count {
                let batch = missing[index..<min(index + 8, missing.count)]
                let found = await withTaskGroup(of: (String, String?).self) { group in
                    for item in batch {
                        let itemKey = key(item)
                        group.addTask { (itemKey, await lookUp(item, region)) }
                    }
                    var results: [(String, String?)] = []
                    for await result in group { results.append(result) }
                    return results
                }
                for (itemKey, rating) in found { certifications[itemKey] = .some(rating) }
                index += 8
            }
        }
        return candidates.filter { item in
            let rating = certifications[key(item)] ?? nil
            return allows(rating: rating, kind: item.mediaType == .tv ? "Series" : "Movie")
        }
    }

    /// A Seerr title's rating, if it has been looked up.
    func certification(for item: SeerrItem) -> String? {
        certifications[key(item)] ?? nil
    }

    private func key(_ item: SeerrItem) -> String {
        "\(item.mediaType == .tv ? "tv" : "movie"):\(item.id)"
    }

    // MARK: - Access schedule

    /// Whether the profile's access schedule allows using the server at `date`. No schedule
    /// means any time. Uses this device's clock and time zone.
    func isWithinSchedule(at date: Date = Date()) -> Bool {
        let schedules = policy.accessSchedules
        guard !schedules.isEmpty else { return true }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
        return schedules.contains { schedule in
            Self.matches(schedule.dayOfWeek, weekday: weekday) && hour >= schedule.startHour && hour < schedule.endHour
        }
    }

    /// When the schedule next allows access, within the coming week.
    func nextAllowedTime(after date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        for minutes in stride(from: 15, through: 7 * 24 * 60, by: 15) {
            let candidate = calendar.date(byAdding: .minute, value: minutes, to: date)!
            let rounded = calendar.date(bySetting: .second, value: 0, of: candidate) ?? candidate
            if isWithinSchedule(at: rounded) { return rounded }
        }
        return nil
    }

    /// Calendar weekdays run 1 (Sunday) to 7 (Saturday).
    private static func matches(_ day: String, weekday: Int) -> Bool {
        switch day {
        case "Everyday": return true
        case "Weekday": return (2...6).contains(weekday)
        case "Weekend": return weekday == 1 || weekday == 7
        default:
            let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            return names.firstIndex(of: day).map { $0 + 1 == weekday } ?? false
        }
    }

    static func describe(_ schedule: AccessSchedule) -> String {
        let day: String = switch schedule.dayOfWeek {
        case "Everyday": "Every day"
        case "Weekday": "Weekdays"
        case "Weekend": "Weekends"
        default: schedule.dayOfWeek
        }
        return "\(day), \(timeLabel(schedule.startHour))–\(timeLabel(schedule.endHour))"
    }

    private static func timeLabel(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        var components = DateComponents()
        components.hour = (total / 60) % 24
        components.minute = total % 60
        guard let date = Calendar.current.date(from: components) else { return "\(hours)" }
        return hours >= 24 ? "midnight" : date.formatted(date: .omitted, time: .shortened)
    }
}
