// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

enum LibraryLetterIndex {
    /// "#" covers titles that start with a number or symbol, which sort before A.
    static let letters = ["#"] + (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) }
}
