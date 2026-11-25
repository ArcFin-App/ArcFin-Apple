// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network
import Observation
import os
import Telemetry

/// The Privacy Policy, Terms of Use, Data Protection notice and every licence, downloaded from
/// the website (arcfin-site scripts/legal.py), which is the only place they're kept. Nothing
/// is built into the app: the last download is kept on the device and shown until a newer one
/// arrives, so the screen works offline once it has loaded.
@MainActor
@Observable
final class LegalLibrary {
    enum Status: Equatable {
        case idle
        case loading
        case failed
    }

    private(set) var documents: [LegalDocument] = []
    private(set) var sources: LegalSources?
    private(set) var licenses: [ThirdPartyLicense] = []
    /// When the copy shown was last checked against the website.
    private(set) var checked: Date?
    private(set) var status: Status = .idle
    /// A download got through this launch, so opening the screen needn't ask again.
    private(set) var isCurrent = false

    var hasContent: Bool { !documents.isEmpty || !licenses.isEmpty || sources != nil }

    static let site = URL(string: "https://arcfin.psmattas.com/legal/v1/")!
    /// The v1 files say which shape they have; a newer one this build can't read is skipped.
    private static let schema = 1

    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private let log = Telemetry.logger(category: "Legal")
    @ObservationIgnored private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    init() {
        restore()
    }

    /// Asks the website for anything newer. Concurrent calls share one download.
    func refresh() async {
        if let running {
            await running.value
            return
        }
        let task = Task { await download() }
        running = task
        await task.value
        running = nil
    }

    private func download() async {
        status = .loading
        await Self.waitForNetworkPath()
        var meta = Meta.read(from: folder)
        do {
            let index: LegalIndex? = try await fetch(Self.site.appending(path: "index.json"), into: "index.json",
                                                     shown: !documents.isEmpty, meta: &meta)
            let licenceFile = try await fetchLicences(meta: &meta)
            if let index, index.schema == Self.schema { show(index) }
            if let licenceFile, licenceFile.schema == Self.schema { licenses = Self.forThisPlatform(licenceFile.components) }
            meta.checked = .now
            meta.write(to: folder)
            checked = meta.checked
            isCurrent = true
            status = .idle
        } catch {
            log.notice("Couldn't download the legal texts: \(error.localizedDescription, privacy: .public)")
            status = .failed
        }
    }

    /// This build's own licences, or the newest when the website has none for it (a build
    /// made on someone's Mac, or a nightly whose release has been removed).
    private func fetchLicences(meta: inout Meta) async throws -> LicenseFile? {
        let own = Self.site.appending(path: "licenses/\(AppBuild.version)-\(AppBuild.number).json")
        do {
            return try await fetch(own, into: "licenses.json", shown: !licenses.isEmpty, meta: &meta)
        } catch LegalDownloadError.notFound {
            return try await fetch(Self.site.appending(path: "licenses/latest.json"), into: "licenses.json",
                                  shown: !licenses.isEmpty, meta: &meta)
        }
    }

    /// The file at `url`, saved as `name`, or nil when it hasn't changed since the copy shown.
    private func fetch<T: Decodable>(_ url: URL, into name: String, shown: Bool, meta: inout Meta) async throws -> T? {
        var request = URLRequest(url: url)
        let saved = folder.appending(path: name)
        if shown, meta.sources[name] == url.absoluteString, let tag = meta.etags[name] {
            request.setValue(tag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 304 { return nil }
        if status == 404 { throw LegalDownloadError.notFound }
        guard (200..<300).contains(status) else { throw LegalDownloadError.status(status) }
        let decoded = try JSONDecoder().decode(T.self, from: data)
        try data.write(to: saved, options: .atomic)
        meta.etags[name] = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag")
        meta.sources[name] = url.absoluteString
        return decoded
    }

    private func restore() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: folder.appending(path: "index.json")),
           let index = try? decoder.decode(LegalIndex.self, from: data), index.schema == Self.schema {
            show(index)
        }
        if let data = try? Data(contentsOf: folder.appending(path: "licenses.json")),
           let file = try? decoder.decode(LicenseFile.self, from: data), file.schema == Self.schema {
            licenses = Self.forThisPlatform(file.components)
        }
        checked = Meta.read(from: folder).checked
    }

    private func show(_ index: LegalIndex) {
        documents = index.documents
        sources = index.sources
    }

    private static func forThisPlatform(_ all: [ThirdPartyLicense]) -> [ThirdPartyLicense] {
        all.filter { $0.platforms?.contains(PlatformMetrics.licensePlatform) ?? true }
    }

    private let folder: URL = {
        let base = FileManager.default.urls(for: PlatformMetrics.keptFilesDirectory, in: .userDomainMask)[0]
        let url = base.appending(path: "Legal", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// A request fired before the network path is up fails at once even with
    /// waitsForConnectivity (CLAUDE.md, cold-launch race), and this one runs at launch.
    private static func waitForNetworkPath(timeoutSeconds: Double = 6) async {
        await withCheckedContinuation { continuation in
            PathWait(continuation: continuation).start(timeoutSeconds: timeoutSeconds)
        }
    }

    /// Beside the saved files rather than in UserDefaults: it's a cache, not a setting.
    private struct Meta: Codable {
        var etags: [String: String] = [:]
        var sources: [String: String] = [:]
        var checked: Date?

        static func read(from folder: URL) -> Meta {
            guard let data = try? Data(contentsOf: folder.appending(path: "meta.json")),
                  let meta = try? JSONDecoder().decode(Meta.self, from: data) else { return Meta() }
            return meta
        }

        func write(to folder: URL) {
            guard let data = try? JSONEncoder().encode(self) else { return }
            try? data.write(to: folder.appending(path: "meta.json"), options: .atomic)
        }
    }
}

enum LegalDownloadError: Error {
    case notFound
    case status(Int)
}

/// /legal/v1/index.json.
struct LegalIndex: Decodable {
    let schema: Int
    let documents: [LegalDocument]
    let sources: LegalSources?
}

/// The services Arcfin credits for its data, each in every language the app has.
struct LegalSources: Decodable, Hashable {
    struct Item: Decodable, Hashable, Identifiable {
        let id: String
        let text: [String: String]
        let platforms: [String]?
    }

    let title: [String: String]
    let items: [Item]

    /// The items that apply on this platform.
    var shown: [Item] {
        items.filter { $0.platforms?.contains(PlatformMetrics.licensePlatform) ?? true }
    }

    /// The app's language (Settings › Language follows the bundle's choice), else English.
    static func localized(_ text: [String: String]) -> String {
        for code in Bundle.main.preferredLocalizations {
            if let value = text[code] { return value }
            if let base = code.split(separator: "-").first, let value = text[String(base)] { return value }
        }
        return text["en"] ?? text.values.first ?? ""
    }
}

/// The Privacy Policy, Terms of Use or Data Protection notice, as Markdown.
struct LegalDocument: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    /// The date the website gives, in its own words ("25 November 2026").
    let effective: String
    let url: String
    let format: String?
    let text: String

    /// In the app's language; the text itself is the binding English.
    var displayName: String {
        switch id {
        case "privacy": String(localized: "Privacy Policy")
        case "terms": String(localized: "Terms of Use")
        case "data-protection": String(localized: "Data Protection")
        default: title
        }
    }
}

/// /legal/v1/licenses/<version>-<build>.json, made for each build by
/// .gitea/scripts/update-licenses.py.
struct LicenseFile: Decodable {
    let schema: Int
    let components: [ThirdPartyLicense]
}

/// One component Arcfin ships and its licence texts.
struct ThirdPartyLicense: Decodable, Identifiable, Hashable {
    struct LicenseText: Decodable, Hashable {
        let title: String
        /// "markdown", or "text" for a plain licence file.
        let format: String?
        let text: String

        var isMarkdown: Bool { format == "markdown" }
    }

    let id: String
    let name: String
    let version: String
    let license: String
    let url: String
    let note: String?
    let platforms: [String]?
    /// "arcfin" for Arcfin's own licence and trademark policy; nil for third-party components.
    let group: String?
    let texts: [LicenseText]

    var isArcfin: Bool { group == "arcfin" }

    /// Arcfin's licence and trademark policy have no version in the file; they're this app's.
    var shownVersion: String { version.isEmpty ? AppBuild.version : version }

    /// Arcfin's own documents in the app's language; everything else by its own name.
    var displayName: String {
        switch id {
        case "arcfin-trademark": String(localized: "Arcfin Name and Logo")
        case "apple-eula": String(localized: "Apple Standard EULA")
        default: name
        }
    }
}
