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

    /// The time zone identifier at the time the roll was loaded (e.g., "America/Los_Angeles")
    var timeZoneIdentifier: String?

    /// Geocoded city/locality name at the time the roll was loaded (e.g., "Los Angeles")
    var cityName: String?

    /// Optional notes for this roll
    var notes: String?

    /// The log items (frames) in this roll
    @Relationship(deleteRule: .cascade, inverse: \LogItem.roll)
    var logItems: [LogItem]?

    init(filmStock: String, camera: Camera? = nil, capacity: Int = 36, createdAt: Date = Date()) {
        self.id = UUID()
        self.filmStock = filmStock
        self.camera = camera
        self.capacity = capacity
        self.createdAt = createdAt
        self.timeZoneIdentifier = TimeZone.current.identifier
    }

    /// Total capacity including extra pre-first-frame exposures
    var totalCapacity: Int { capacity + extraExposures }

    // MARK: - Snapshot (Roll's own fields only — derived data computed by loadAll)

    func snapshot(formatters: SnapshotDateFormatters) -> RollSnapshot {
        let (capturedTZ, hasDifferentTZ, capturedTZLabel) = formatters.timeZoneInfo(for: createdAt, tzIdentifier: timeZoneIdentifier, cityName: cityName)
        let (capTimeFmt, capDateFmt) = formatters.captured(for: capturedTZ)

        return RollSnapshot(
            id: id,
            cameraID: camera?.id,
            filmStock: filmStock,
            capacity: capacity,
            extraExposures: extraExposures,
            isActive: isActive,
            createdAt: createdAt,
            timeZoneIdentifier: timeZoneIdentifier,
            cityName: cityName,
            notes: notes,
            lastExposureDate: nil,
            exposureCount: 0,
            totalCapacity: totalCapacity,
            formattedTime: createdAt.formatted(capTimeFmt),
            formattedDate: createdAt.formatted(capDateFmt),
            localFormattedTime: createdAt.formatted(formatters.localTime),
            localFormattedDate: createdAt.formatted(formatters.localDate),
            hasDifferentTimeZone: hasDifferentTZ,
            capturedTZLabel: capturedTZLabel
        )
    }

    /// Convenience for single-roll snapshot (e.g. previews) where formatter reuse doesn't matter.
    var snapshot: RollSnapshot {
        snapshot(formatters: SnapshotDateFormatters())
    }
}
