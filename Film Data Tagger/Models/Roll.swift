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

    /// The camera this roll is loaded in (nil for instant film packs)
    var camera: Camera?

    /// The instant film camera this pack belongs to (nil for regular rolls)
    var instantFilmCamera: InstantFilmCamera?

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
}
