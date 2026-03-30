//
//  CameraListEntry.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/20/26.
//

import Foundation

/// Protocol for items that appear in the camera list.
/// Display-only — no SwiftData.
///
/// Properties accessed from view bodies must be cheap — no relationship faulting.
/// CameraSnapshot and RollSnapshot are value types with all display data pre-computed by loadAll.
///
/// Date semantics:
/// - Cameras own no dates. Their displayed "last used" is the latest roll date.
/// - Rolls own one stored date: `createdAt` (immutable). `lastExposureDate` (latest real
///   exposure's createdAt) is computed by loadAll from items.
///   The displayed "last used" is `lastExposureDate ?? createdAt`.
/// - Exposures own one immutable date: `createdAt`.
protocol CameraListEntry: Identifiable where ID == UUID {
    var id: UUID { get }
    var name: String { get }
    var createdAt: Date { get }
    var listOrder: Double { get }
    var isInstantFilm: Bool { get }
    var rollCount: Int { get }
    var totalExposureCount: Int { get }
    var activeExposureCount: Int? { get }
    var activeCapacity: Int? { get }
    var activeRollID: UUID? { get }
    var activeFilmStock: String? { get }
    var lastUsedDate: Date? { get }
}

// MARK: - Display helpers

extension CameraListEntry {
    var filmStockLabel: String? {
        activeFilmStock ?? (rollCount > 0 ? "no roll loaded" : nil)
    }

    var lastUsedCompact: String? {
        guard let date = lastUsedDate else { return nil }
        return relativeTimeString(from: date)
    }
}

// MARK: - CameraSnapshot conformance

extension CameraSnapshot: CameraListEntry {
    var isInstantFilm: Bool { false }
    var activeRollID: UUID? { activeRoll?.id }
    var activeFilmStock: String? { activeRoll?.filmStock }
    var activeExposureCount: Int? { activeRoll?.exposureCount }
    var activeCapacity: Int? { activeRoll?.totalCapacity }
}
