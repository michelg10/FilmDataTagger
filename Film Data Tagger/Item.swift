//
//  Item.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
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
