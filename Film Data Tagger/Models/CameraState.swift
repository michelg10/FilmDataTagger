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

    /// Past (inactive) rolls sorted by most recent use. Rebuilt by `recomputeRollDisplayData()`.
    private(set) var pastRolls: [RollSnapshot] = []
    /// Largest totalCapacity across all rolls, for progress bar scaling.
    private(set) var maxRollCapacity: Int = 36

    init(snapshot: CameraSnapshot, rolls: [RollState] = []) {
        self.id = snapshot.id
        self.snapshot = snapshot
        self.rolls = rolls
        self.activeRoll = rolls.first(where: { $0.snapshot.isActive })
        self.snapshot.activeRoll = self.activeRoll?.snapshot
        recomputeRollDisplayData()
    }

    /// Rebuild pastRolls and maxRollCapacity from current rolls.
    func recomputeRollDisplayData() {
        pastRolls = rolls
            .filter { !$0.snapshot.isActive }
            .map(\.snapshot)
            .sorted { ($0.lastExposureDate ?? $0.createdAt) > ($1.lastExposureDate ?? $1.createdAt) }
        maxRollCapacity = rolls.map(\.snapshot.totalCapacity).max() ?? 36
    }
}

// CameraListEntry conformance is on CameraSnapshot directly — views never see CameraState.
