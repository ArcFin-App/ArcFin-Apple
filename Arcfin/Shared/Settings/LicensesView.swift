// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Settings › Legal & Licenses. Everything on it comes from the website through
/// `LegalLibrary`; the app carries no copy of its own.
struct LicensesView: View {
    private let library = AppServices.legal

    var body: some View {
        List {
            if let sources = library.sources {
                Section {
                    ForEach(sources.shown) { item in
                        Text(verbatim: LegalSources.localized(item.text))
                            .tvReadOnlyRow()
                    }
                } header: {
                    Text(verbatim: LegalSources.localized(sources.title))
                }
            }
            if library.hasContent {
                Section {
                    ForEach(library.documents) { document in
                        NavigationLink {
                            LegalDocumentView(document: document)
                        } label: {
                            LicenseRow(name: document.displayName, license: "Arcfin", note: document.effective)
                        }
                    }
                    ForEach(library.licenses.filter(\.isArcfin)) { entry in
                        row(entry)
                    }
                } header: {
                    Text(verbatim: "Arcfin")
                } footer: {
                    Text("Arcfin's own licence, trademark policy and legal terms, as the website publishes them now.")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Section {
                    ForEach(library.licenses.filter { !$0.isArcfin }) { entry in
                        row(entry)
                    }
                } footer: {
                    Text("Open-source and third-party components Arcfin includes. Each shows its full licence, as written, and the exact version Arcfin is built with.")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            LegalStatusSection(library: library)
        }
        .arcfinListStyle()
        .screenBackground()
        .navigationTitle("Legal & Licenses")
        .inlineNavigationTitle()
        .refreshable { await library.refresh() }
        .task { if !library.isCurrent { await library.refresh() } }
    }

    private func row(_ entry: ThirdPartyLicense) -> some View {
        NavigationLink {
            LicenseDetailView(entry: entry)
        } label: {
            LicenseRow(name: entry.displayName, license: entry.license, note: entry.shownVersion)
        }
    }
}

/// Whether the texts above are current, and a way to ask again.
private struct LegalStatusSection: View {
    let library: LegalLibrary

    var body: some View {
        Section {
            Button {
                Task { await library.refresh() }
            } label: {
                HStack {
                    Text(library.status == .failed && !library.hasContent ? "Try Again" : "Refresh")
                    Spacer()
                    if library.status == .loading {
                        ProgressView()
                    }
                }
            }
            .disabled(library.status == .loading)
        } footer: {
            footer
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if library.status == .failed && !library.hasContent {
            Text("Couldn't load the legal texts and licences from the website. Check your connection and try again.")
        } else if library.status == .failed, let checked = library.checked {
            Text("Couldn't reach the website, so this is the copy from \(checked.formatted(date: .abbreviated, time: .shortened)).")
        } else if library.status == .loading && !library.hasContent {
            Text("Loading the legal texts and licences from the website…")
        } else if let checked = library.checked {
            Text("Checked with the website \(checked.formatted(date: .abbreviated, time: .shortened)).")
        }
    }
}

/// The Privacy Policy, Terms of Use or Data Protection notice, as the website has it.
struct LegalDocumentView: View {
    let document: LegalDocument
    @State private var blocks: [MarkdownBlock] = []

    var body: some View {
        List {
            Section {
                LabeledContent("Effective") { Text(verbatim: document.effective) }
                    .tvReadOnlyRow()
                if let url = URL(string: document.url) {
                    LicenseSourceRow(title: "Website", url: url)
                }
            }
            Section {
                ForEach(blocks) { block in
                    MarkdownBlockView(block: block)
                        .tvReadOnlyRow()
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .navigationTitle(Text(verbatim: document.displayName))
        .inlineNavigationTitle()
        .tvSettingsPage()
        .task(id: document) { blocks = MarkdownBlock.parse(document.text) }
    }
}

/// A component's version, source and licence texts. The texts are shown as their authors
/// wrote them, in English, and never go through the String Catalog.
struct LicenseDetailView: View {
    let entry: ThirdPartyLicense
    /// Each Markdown text's blocks, parsed once when the page opens: some texts are long.
    @State private var parsed: [ThirdPartyLicense.LicenseText: [MarkdownBlock]] = [:]

    var body: some View {
        List {
            Section {
                LabeledContent("Version") { Text(verbatim: entry.shownVersion) }
                    .tvReadOnlyRow()
                LabeledContent("License") { Text(verbatim: entry.license) }
                    .tvReadOnlyRow()
                if let url = URL(string: entry.url) {
                    if entry.isArcfin && entry.id != "arcfin" {
                        LicenseSourceRow(title: "Website", url: url)
                    } else {
                        LicenseSourceRow(title: "Source Code", url: url)
                    }
                }
            } footer: {
                if let note = entry.note {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            ForEach(entry.texts, id: \.self) { text in
                Section {
                    LicenseTextRows(text: text, blocks: parsed[text] ?? [])
                } header: {
                    Text(verbatim: text.title)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .navigationTitle(Text(verbatim: entry.displayName))
        .inlineNavigationTitle()
        .tvSettingsPage()
        .task(id: entry) {
            parsed = Dictionary(entry.texts.filter(\.isMarkdown).map { ($0, MarkdownBlock.parse($0.text)) },
                                uniquingKeysWith: { first, _ in first })
        }
    }
}

/// One licence text, drawn like the legal pages.
private struct LicenseTextRows: View {
    let text: ThirdPartyLicense.LicenseText
    let blocks: [MarkdownBlock]

    var body: some View {
        if text.isMarkdown {
            ForEach(blocks) { block in
                MarkdownBlockView(block: block)
                    .tvReadOnlyRow()
            }
        } else {
            ForEach(Array(PlainTextBlocks.chunks(of: text.text).enumerated()), id: \.offset) { _, chunk in
                Text(verbatim: chunk)
                    .font(.footnote)
                    .foregroundStyle(DT.Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tvReadOnlyRow()
            }
        }
    }
}
