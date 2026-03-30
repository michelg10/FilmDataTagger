//
//  CameraState.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/29/26.
//

import Foundation

@Observable
final class CameraState: Identifiable, Sendable {
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
    }
}

// MARK: - CameraListEntry conformance (forwards to snapshot)

extension CameraState: CameraListEntry {
    var name: String { snapshot.name }
    var createdAt: Date { snapshot.createdAt }
    var listOrder: Double { snapshot.listOrder }
    var isInstantFilm: Bool { snapshot.isInstantFilm }
    var rollCount: Int { snapshot.rollCount }
    var totalExposureCount: Int { snapshot.totalExposureCount }
    var activeExposureCount: Int? { snapshot.activeExposureCount }
    var activeCapacity: Int? { snapshot.activeCapacity }
    var activeFilmStock: String? { snapshot.activeFilmStock }
    var activeRollID: UUID? { snapshot.activeRollID }
    var lastUsedDate: Date? { snapshot.lastUsedDate }
    // filmStockLabel and lastUsedCompact come from the CameraListEntry extension
}
