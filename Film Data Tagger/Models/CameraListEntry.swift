//
//  CameraListEntry.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/20/26.
//

import Foundation

/// Protocol for items that appear in the camera list.
/// Camera conforms via @Model.
///
/// Properties accessed from view bodies must be cheap — no relationship faulting.
/// Camera uses cached summary fields maintained by the ViewModel.
///
/// Date semantics:
/// - Cameras own no dates. Their displayed "last used" is the latest roll date.
/// - Rolls own one stored date: `createdAt` (immutable). They also cache
///   `lastExposureDate` (latest real exposure's createdAt, maintained by the ViewModel).
///   The displayed "last used" is `lastExposureDate ?? createdAt`.
/// - Exposures own one immutable date: `createdAt`.
@MainActor
protocol CameraListEntry {
    var id: UUID { get }
    var createdAt: Date { get }
    var listOrder: Double { get set }
    var displayName: String { get }
    var isInstantFilm: Bool { get }
    /// All rolls for this entry. Faults relationships — do NOT call from view bodies.
    var allRolls: [Roll] { get }
    var activeRoll: Roll? { get }
    var rollCount: Int { get }
    var totalExposureCount: Int { get }
    /// Exposure count on the active roll (for progress ring). Nil if no active roll.
    var activeExposureCount: Int? { get }
    /// Total capacity of the active roll (for progress ring). Nil if no active roll.
    var activeCapacity: Int? { get }
    var filmStockLabel: String? { get }
    var lastUsedCompact: String? { get }
}


// MARK: - Camera conformance (uses cached fields — safe for view bodies)

extension Camera: CameraListEntry {
    var displayName: String { name }
    var isInstantFilm: Bool { false }
    var allRolls: [Roll] { rolls ?? [] }

    var activeRoll: Roll? {
        // This faults the rolls relationship — avoid calling from view bodies.
        // View bodies should use cachedActiveExposureCount/cachedActiveCapacity instead.
        allRolls.first(where: \.isActive)
    }

    var rollCount: Int { cachedRollCount }
    var totalExposureCount: Int { cachedTotalExposureCount }
    var activeExposureCount: Int? { cachedActiveExposureCount }
    var activeCapacity: Int? { cachedActiveCapacity }

    var filmStockLabel: String? {
        cachedActiveFilmStock ?? (cachedRollCount > 0 ? "no roll loaded" : nil)
    }

    var lastUsedCompact: String? {
        guard let date = cachedLastUsedDate else { return nil }
        return relativeTimeString(from: date)
    }
}
