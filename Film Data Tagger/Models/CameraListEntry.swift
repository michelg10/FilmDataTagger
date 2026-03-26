//
//  CameraListEntry.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/20/26.
//

import Foundation

/// Protocol for items that appear in the camera list (regular cameras and instant film groups).
/// Both Camera and InstantFilmGroup already conform to Identifiable via @Model.
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
    var allRolls: [Roll] { get }
    var activeRoll: Roll? { get }
    var rollCount: Int { get }
    var totalExposureCount: Int { get }
    var filmStockLabel: String? { get }
    var lastUsedCompact: String? { get }
}

// MARK: - Default implementations

extension CameraListEntry {
    var rollCount: Int { allRolls.count }

    var totalExposureCount: Int {
        allRolls.reduce(0) { $0 + ($1.logItems ?? []).count }
    }

    var lastUsedCompact: String? {
        guard !allRolls.isEmpty else { return nil }
        let lastDate = allRolls.map { $0.lastExposureDate ?? $0.createdAt }.max()!
        return relativeTimeString(from: lastDate)
    }
}


// MARK: - Camera conformance

extension Camera: CameraListEntry {
    var displayName: String { name }
    var isInstantFilm: Bool { false }
    var allRolls: [Roll] { rolls ?? [] }
    var activeRoll: Roll? { allRolls.first(where: { $0.isActive }) }

    var filmStockLabel: String? {
        activeRoll?.filmStock ?? (allRolls.isEmpty ? nil : "no roll loaded")
    }
}

// MARK: - InstantFilmGroup conformance

extension InstantFilmGroup: CameraListEntry {
    var displayName: String { name }
    var isInstantFilm: Bool { true }
    var allRolls: [Roll] { (cameras ?? []).flatMap { $0.rolls ?? [] } }
    var activeRoll: Roll? { nil }

    var filmStockLabel: String? { nil }
}
