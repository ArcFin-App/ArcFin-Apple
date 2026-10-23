// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import AuthCore
import JellyfinAPI
import SeerrAPI
import Telemetry
import os

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
        if let serverDate = await client.getServerDate(baseURL: credential.baseURL) {
            TrustedClock.anchor(to: serverDate)
        }
        async let fetchedProfile = try? client.getUserProfile(credential: credential, authHeader: authHeader)
        async let fetchedRatings = try? client.getParentalRatings(credential: credential, authHeader: authHeader)
        let (newProfile, newRatings) = await (fetchedProfile, fetchedRatings)
        // A failed fetch keeps the previous profile's rules rather than dropping them, so a
        // restricted profile never briefly sees everything over a flaky connection.
        if let newProfile { profile = newProfile }
        if let newRatings, !newRatings.isEmpty { ratings = newRatings }
    }

    func clear() {
        profile = nil
        certifications = [:]
        failedLookups = [:]
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
    func visible(_ items: [SeerrItem], region: String, lookUp: @escaping @Sendable (SeerrItem, String) async -> String?) async -> [SeerrItem] {
        // Seerr's titles are only filtered when the profile has a maximum rating: that's the
        // limit that can be checked against a title outside the library. Tags only exist in
        // the library, and the unrated rule applies alongside the maximum.
        guard policy.maxParentalRating != nil else { return items }
        let candidates = items.filter { !$0.isAdult }

        loadSavedCertifications(region: region)
        let now = Date()
        let missing = candidates.filter { item in
            let itemKey = key(item, region)
            guard certifications[itemKey] == nil else { return false }
            // A title whose lookup just failed isn't asked again on every keystroke.
            if let failed = failedLookups[itemKey], now.timeIntervalSince(failed) < Self.failedLookupRetry { return false }
            return true
        }
        if !missing.isEmpty {
            // Up to 16 in flight, each a detail request to the Seerr server. The whole batch
            // gets a deadline: a slow or overloaded Seerr would otherwise hold the list for
            // as long as its slowest answers, and what's still out is treated as unrated.
            let found = await withTaskGroup(of: (String, String?)?.self) { group in
                var results: [(String, String?)] = []
                var iterator = missing.makeIterator()
                group.addTask {
                    try? await Task.sleep(for: Self.lookupDeadline)
                    return nil
                }
                for _ in 0..<16 {
                    guard let item = iterator.next() else { break }
                    let itemKey = key(item, region)
                    group.addTask { (itemKey, await lookUp(item, region)) }
                }
                while let next = await group.next() {
                    guard let result = next else {
                        group.cancelAll()
                        break
                    }
                    results.append(result)
                    if let item = iterator.next() {
                        let itemKey = key(item, region)
                        group.addTask { (itemKey, await lookUp(item, region)) }
                    }
                    if results.count == missing.count {
                        group.cancelAll()
                        break
                    }
                }
                return results
            }
            // The lookup answers "" for a title with no rating and nil when it couldn't ask;
            // only real answers are remembered, so a failed lookup is tried again later.
            var answered = Set<String>()
            for (itemKey, rating) in found {
                guard let rating else { continue }
                answered.insert(itemKey)
                certifications[itemKey] = .some(rating.isEmpty ? nil : rating)
                failedLookups[itemKey] = nil
            }
            for item in missing where !answered.contains(key(item, region)) {
                failedLookups[key(item, region)] = now
            }
            if !answered.isEmpty { saveCertifications() }
            let unanswered = missing.count - answered.count
            if unanswered > 0 {
                Self.log.info("Seerr rating lookups: \(answered.count, privacy: .public) answered, \(unanswered, privacy: .public) failed or timed out")
            }
        }
        let kept = candidates.filter { item in
            let rating = certifications[key(item, region)] ?? nil
            return allows(rating: rating, kind: item.mediaType == .tv ? "Series" : "Movie")
        }
        Self.log.info("Seerr list filtered for parental controls: kept \(kept.count, privacy: .public) of \(items.count, privacy: .public)")
        return kept
    }

    private static let log = Telemetry.logger(category: "ProfileRules")
    private static let lookupDeadline: Duration = .seconds(6)
    private static let failedLookupRetry: TimeInterval = 10 * 60
    @ObservationIgnored private var failedLookups: [String: Date] = [:]
    private static let savedCertificationsKey = "arcfin.seerrCertifications"
    @ObservationIgnored private var loadedSavedCertifications = false

    /// Ratings rarely change, so they're kept between launches (as "" for none known).
    private func loadSavedCertifications(region: String) {
        guard !loadedSavedCertifications else { return }
        loadedSavedCertifications = true
        let saved = UserDefaults.standard.dictionary(forKey: Self.savedCertificationsKey) as? [String: String] ?? [:]
        for (itemKey, rating) in saved where certifications[itemKey] == nil {
            certifications[itemKey] = .some(rating.isEmpty ? nil : rating)
        }
    }

    private func saveCertifications() {
        var saved: [String: String] = [:]
        for (itemKey, rating) in certifications.suffix(4000) { saved[itemKey] = rating ?? "" }
        UserDefaults.standard.set(saved, forKey: Self.savedCertificationsKey)
    }

    /// A Seerr title's rating, if it has been looked up.
    func certification(for item: SeerrItem, region: String) -> String? {
        certifications[key(item, region)] ?? nil
    }

    private func key(_ item: SeerrItem, _ region: String) -> String {
        "\(region):\(item.mediaType == .tv ? "tv" : "movie"):\(item.id)"
    }

    // MARK: - Access schedule

    /// Whether the profile's access schedule allows using the server at `date` (by default
    /// the trusted time, not the device's clock setting). No schedule means any time.
    func isWithinSchedule(at date: Date = TrustedClock.now) -> Bool {
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
    func nextAllowedTime(after date: Date = TrustedClock.now) -> Date? {
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

/// The current time as the server last told it, carried forward by a counter that runs from
/// boot (through sleep) and that changing the device's date and time doesn't touch — so the
/// access schedule can't be dodged by setting the clock back. Falls back to the device clock
/// only before the server has been reached since the device last restarted.
nonisolated enum TrustedClock {
    private static let serverDateKey = "arcfin.trustedClock.serverDate"
    private static let monotonicKey = "arcfin.trustedClock.monotonic"

    static func anchor(to serverDate: Date) {
        UserDefaults.standard.set(serverDate.timeIntervalSince1970, forKey: serverDateKey)
        UserDefaults.standard.set(monotonicSeconds, forKey: monotonicKey)
    }

    static var now: Date {
        let defaults = UserDefaults.standard
        let anchorDate = defaults.double(forKey: serverDateKey)
        let anchorMonotonic = defaults.double(forKey: monotonicKey)
        let elapsed = monotonicSeconds - anchorMonotonic
        // The counter starts again from zero on restart, which makes an old anchor unusable.
        guard anchorDate > 0, elapsed >= 0 else { return Date() }
        return Date(timeIntervalSince1970: anchorDate + elapsed)
    }

    /// Seconds since boot, including time asleep.
    private static var monotonicSeconds: Double {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}
