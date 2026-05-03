//
//  Item.swift
//  Arcfin
//
//  Created by Puranjay Savar Mattas on 03/05/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
