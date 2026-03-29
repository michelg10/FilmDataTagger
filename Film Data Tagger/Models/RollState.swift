//
//  RollState.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/29/26.
//

import Foundation

@Observable
final class RollState: Identifiable {
    let id: UUID
    var snapshot: RollSnapshot
    var items: [LogItemSnapshot]

    init(snapshot: RollSnapshot, items: [LogItemSnapshot] = []) {
        self.id = snapshot.id
        self.snapshot = snapshot
        self.items = items
    }
}
