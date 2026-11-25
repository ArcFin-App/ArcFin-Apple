// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SwiftUI

/// Markdown cut into blocks, with Foundation's own parser, so each heading, paragraph, list
/// item, quote and table row is a row of its own: a long text scrolls in small pieces, and
/// the Apple TV remote can move through it.
struct MarkdownBlock: Identifiable, Hashable {
    enum Kind: Hashable {
        case heading(Int)
        case paragraph
        case quote
        /// The marker shown before it: "•" or "3.".
        case listItem(String)
        case code
        /// A table row, each cell with its column's heading.
        case tableRow([MarkdownCell])
    }

    let id: Int
    let kind: Kind
    let text: AttributedString

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return [MarkdownBlock(id: 0, kind: .paragraph, text: AttributedString(markdown))]
        }
        var pieces: [(intent: PresentationIntent?, text: AttributedString)] = []
        for (intent, range) in parsed.runs[\.presentationIntent] {
            var text = AttributedString(parsed[range])
            text.presentationIntent = nil
            if let last = pieces.last, last.intent == intent {
                pieces[pieces.count - 1].text += text
            } else {
                pieces.append((intent, text))
            }
        }

        var blocks: [MarkdownBlock] = []
        var headings: [Int: AttributedString] = [:]
        var row: (identity: Int, cells: [MarkdownCell])?
        func finishRow() {
            guard let current = row else { return }
            blocks.append(MarkdownBlock(id: blocks.count, kind: .tableRow(current.cells), text: AttributedString()))
            row = nil
        }

        for piece in pieces {
            let components = piece.intent?.components ?? []
            if let cell = components.first(where: { if case .tableCell = $0.kind { true } else { false } }),
               case .tableCell(let column) = cell.kind {
                let isHeader = components.contains { $0.kind == .tableHeaderRow }
                if isHeader {
                    headings[column] = piece.text
                    continue
                }
                let rowIdentity = components.first { if case .tableRow = $0.kind { true } else { false } }?.identity ?? 0
                if row?.identity != rowIdentity {
                    finishRow()
                    row = (rowIdentity, [])
                }
                row?.cells.append(MarkdownCell(heading: headings[column], text: piece.text))
                continue
            }
            finishRow()
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind(of: components), text: piece.text))
        }
        finishRow()
        return blocks
    }

    /// The innermost block a run belongs to decides how it's shown.
    private static func kind(of components: [PresentationIntent.IntentType]) -> Kind {
        for (index, component) in components.enumerated() {
            switch component.kind {
            case .header(let level):
                return .heading(level)
            case .codeBlock:
                return .code
            case .listItem(let ordinal):
                let ordered = components[(index + 1)...].contains { $0.kind == .orderedList }
                return .listItem(ordered ? "\(ordinal)." : "•")
            case .blockQuote:
                return .quote
            default:
                continue
            }
        }
        return .paragraph
    }
}

struct MarkdownCell: Hashable {
    let heading: AttributedString?
    let text: AttributedString
}

/// One block of a Markdown text, in the app's type and colours.
struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        content
            .foregroundStyle(DT.Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(block.text)
                .font(.callout)
        case .quote:
            Text(block.text)
                .font(.callout)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Capsule().fill(DT.Color.accent).frame(width: 3)
                }
        case .listItem(let marker):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: marker)
                    .font(.callout)
                    .foregroundStyle(DT.Color.textSecondary)
                Text(block.text)
                    .font(.callout)
            }
        case .code:
            Text(block.text)
                .font(.system(.caption, design: .monospaced))
        case .tableRow(let cells):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    VStack(alignment: .leading, spacing: 2) {
                        if let heading = cell.heading {
                            Text(heading)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        Text(cell.text)
                            .font(.callout)
                    }
                }
            }
        }
    }
}

/// A plain licence file's paragraphs, long ones cut at line breaks, as written.
enum PlainTextBlocks {
    static func chunks(of text: String, maxLines: Int = 24) -> [String] {
        var out: [String] = []
        for paragraph in text.components(separatedBy: "\n\n") {
            let trimmed = paragraph.trimmingCharacters(in: .newlines)
            guard !trimmed.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let lines = trimmed.components(separatedBy: "\n")
            stride(from: 0, to: lines.count, by: maxLines).forEach {
                out.append(lines[$0..<min($0 + maxLines, lines.count)].joined(separator: "\n"))
            }
        }
        return out
    }
}
