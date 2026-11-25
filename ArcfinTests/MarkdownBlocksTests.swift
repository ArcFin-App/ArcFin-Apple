// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import Arcfin

struct MarkdownBlocksTests {
    private func plain(_ text: AttributedString) -> String {
        String(text.characters)
    }

    @Test func headingsParagraphsAndLists() {
        let blocks = MarkdownBlock.parse("""
        > **In short:** nothing leaves.

        ## What Arcfin connects to

        Arcfin talks to:

        - **Jellyfin** (required)
        - [Seerr](https://example.com)

        1. First
        2. Second
        """)
        #expect(blocks.map(\.kind) == [.quote, .heading(2), .paragraph, .listItem("•"), .listItem("•"),
                                       .listItem("1."), .listItem("2.")])
        #expect(plain(blocks[0].text) == "In short: nothing leaves.")
        #expect(plain(blocks[4].text) == "Seerr")
        #expect(blocks[4].text.runs.contains { $0.link == URL(string: "https://example.com") })
    }

    @Test func tableRowsCarryTheirColumnHeadings() {
        let blocks = MarkdownBlock.parse("""
        | Data | Where |
        | --- | --- |
        | Sign-ins | Your device |
        | Settings | Your server |
        """)
        #expect(blocks.count == 2)
        guard case .tableRow(let cells) = blocks[1].kind else {
            Issue.record("not a table row")
            return
        }
        #expect(cells.map { $0.heading.map { String($0.characters) } } == ["Data", "Where"])
        #expect(cells.map { String($0.text.characters) } == ["Settings", "Your server"])
    }

    @Test func plainTextKeepsParagraphs() {
        let chunks = PlainTextBlocks.chunks(of: "MIT License\n\nCopyright (c) 2026 Someone\n\n\nPermission is granted.\n")
        #expect(chunks == ["MIT License", "Copyright (c) 2026 Someone", "Permission is granted."])
    }
}
