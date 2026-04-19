//
//  Item.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
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
