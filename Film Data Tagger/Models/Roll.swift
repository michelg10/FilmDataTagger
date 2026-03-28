//
//  Roll.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftData

@Model
final class Roll {
    #Index<Roll>([\.id])

    var id: UUID = UUID()

    /// The camera this roll is loaded in
    var camera: Camera?

    /// Film stock name (e.g., "Portra 400", "HP5+")
    var filmStock: String = "SystemReserved:DataError"

    /// Number of frames per roll (e.g., 12, 24, 36)
    var capacity: Int = 36

    /// Number of pre-first-frame exposures (0–4), for carefully loaded rolls
    var extraExposures: Int = 0

    /// Whether this is the active roll for its camera. Only one roll per camera should be active.
    var isActive: Bool = true

    var createdAt: Date = Date.distantPast

    /// The date of the most recent real (non-placeholder) exposure on this roll.
    /// Maintained by the ViewModel; nil if the roll has no real exposures yet.
    var lastExposureDate: Date?

    /// Cached count of logItems. Maintained by the ViewModel to avoid faulting
    /// the logItems relationship just to get a count (expensive in view bodies).
    var exposureCount: Int = 0

    /// The log items (frames) in this roll
    @Relationship(deleteRule: .cascade, inverse: \LogItem.roll)
    var logItems: [LogItem]?

    init(filmStock: String, camera: Camera? = nil, capacity: Int = 36) {
        self.id = UUID()
        self.filmStock = filmStock
        self.camera = camera
        self.capacity = capacity
        self.createdAt = Date()
    }

    /// Total capacity including extra pre-first-frame exposures
    var totalCapacity: Int { capacity + extraExposures }

    // MARK: - Snapshot

    var snapshot: RollSnapshot {
        RollSnapshot(
            id: id,
            filmStock: filmStock,
            capacity: capacity,
            extraExposures: extraExposures,
            isActive: isActive,
            createdAt: createdAt,
            lastExposureDate: lastExposureDate,
            exposureCount: exposureCount,
            totalCapacity: totalCapacity
        )
    }
}
