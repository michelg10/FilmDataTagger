//
//  RollState.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/29/26.
//

import Foundation

final class RollState: Identifiable {
    let id: UUID
    var snapshot: RollSnapshot
    var items: [LogItemSnapshot] { didSet { itemsVersion &+= 1 } }
    private(set) var itemsVersion: Int = 0

    init(snapshot: RollSnapshot, items: [LogItemSnapshot] = []) {
        self.id = snapshot.id
        self.snapshot = snapshot
        self.items = items
    }
}
