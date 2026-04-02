//
//  CameraState.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/29/26.
//

import Foundation

final class CameraState: Identifiable {
    let id: UUID
    var snapshot: CameraSnapshot
    var rolls: [RollState]
    /// Reference to the active roll in `rolls` for O(1) access, no linear scan.
    var activeRoll: RollState?

    init(snapshot: CameraSnapshot, rolls: [RollState] = []) {
        self.id = snapshot.id
        self.snapshot = snapshot
        self.rolls = rolls
        self.activeRoll = rolls.first(where: { $0.snapshot.isActive })
        self.snapshot.activeRoll = self.activeRoll?.snapshot
    }
}

// CameraListEntry conformance is on CameraSnapshot directly — views never see CameraState.
