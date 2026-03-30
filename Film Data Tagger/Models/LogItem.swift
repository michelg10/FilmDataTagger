//
//  LogItem.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftData
import CoreLocation

nonisolated enum ExposureSource: Equatable {
    case app
    case shortcut
    case unknown(String)

    var rawValue: String {
        switch self {
        case .app: "app"
        case .shortcut: "shortcut"
        case .unknown(let value): value
        }
    }

    init(_ rawValue: String) {
        switch rawValue {
        case "app": self = .app
        case "shortcut": self = .shortcut
        default: self = .unknown(rawValue)
        }
    }
}

@Model
final class LogItem {
    #Index<LogItem>([\.id], [\.createdAt], [\.placeName])

    var id: UUID = UUID()

    /// The roll this item belongs to
    var roll: Roll?

    /// When `hasRealCreatedAt` is false, `createdAt` is a synthetic value used only for sort ordering.
    var createdAt: Date = Date.distantPast
    var hasRealCreatedAt: Bool = true

    /// Optional notes for this frame
    var notes: String?

    // MARK: - Location data (max fidelity)
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var horizontalAccuracy: Double?
    var verticalAccuracy: Double?
    var course: Double?
    var speed: Double?
    var locationTimestamp: Date?

    /// Human-readable place name from reverse geocoding (e.g., "Dockweiler State Beach")
    var placeName: String?

    /// Geocoded city/locality name (e.g., "Los Angeles"), used for time zone display
    var cityName: String?

    /// The time zone identifier at the time of capture (e.g., "America/Los_Angeles")
    var timeZoneIdentifier: String?

    /// When true, this item is a placeholder with no captured metadata
    var isPlaceholder: Bool = false

    /// How this exposure was created (raw storage for ExposureSource enum)
    var source: String?

    /// Cached flag: whether photoData is non-nil (avoids faulting external storage on snapshot)
    var cachedHasPhoto: Bool = false

    /// Cached flag: whether thumbnailData is non-nil (avoids faulting inline blob on snapshot)
    var cachedHasThumbnail: Bool = false

    /// Typed accessor for `source`
    @Transient var exposureSource: ExposureSource {
        get { source.map(ExposureSource.init) ?? .app }
        set { source = newValue.rawValue }
    }

    /// Reference photo captured at time of logging (HEIC data, stored externally by SwiftData)
    @Attribute(.externalStorage) var photoData: Data?

    /// Small thumbnail for list display (~180px HEIC, inline in the database)
    var thumbnailData: Data?

    init(roll: Roll) {
        self.id = UUID()
        self.roll = roll
        self.createdAt = Date()
        self.timeZoneIdentifier = TimeZone.current.identifier
        self.isPlaceholder = false
    }

    /// Create a placeholder exposure (no metadata captured)
    static func placeholder(roll: Roll) -> LogItem {
        let item = LogItem(roll: roll)
        item.isPlaceholder = true
        item.hasRealCreatedAt = false
        return item
    }

    /// Capture location data from a CLLocation
    func setLocation(_ location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.course = location.course
        self.speed = location.speed
        self.locationTimestamp = location.timestamp
    }

    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    // MARK: - Snapshot

    var snapshot: LogItemSnapshot {
        // Capture TZ formatting (immutable)
        let capturedTZ = timeZoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
        var capTimeFmt = Date.FormatStyle.dateTime.hour().minute()
        capTimeFmt.timeZone = capturedTZ
        var capDateFmt = Date.FormatStyle.dateTime.month().day().year()
        capDateFmt.timeZone = capturedTZ

        // Device TZ formatting (recomputed by DataStore on TZ change)
        let hasDifferentTZ = capturedTZ.secondsFromGMT(for: createdAt)
            != TimeZone.current.secondsFromGMT(for: createdAt)
        let capturedTZLabel: String? = if hasDifferentTZ {
            cityName ?? timeZoneIdentifier.map { cityName(from: $0) }
        } else {
            nil
        }

        return LogItemSnapshot(
            id: id,
            rollID: roll?.id,
            createdAt: createdAt,
            hasRealCreatedAt: hasRealCreatedAt,
            notes: notes,
            latitude: latitude,
            longitude: longitude,
            placeName: placeName,
            cityName: cityName,
            timeZoneIdentifier: timeZoneIdentifier,
            isPlaceholder: isPlaceholder,
            source: source,
            hasThumbnail: cachedHasThumbnail,
            hasPhoto: cachedHasPhoto,
            formattedTime: createdAt.formatted(capTimeFmt),
            formattedDate: createdAt.formatted(capDateFmt),
            localFormattedTime: createdAt.formatted(.dateTime.hour().minute()),
            localFormattedDate: createdAt.formatted(.dateTime.month().day().year()),
            hasDifferentTimeZone: hasDifferentTZ,
            capturedTZLabel: capturedTZLabel
        )
    }

    /// Extracts a city name from a time zone identifier (e.g., "America/Los_Angeles" → "Los Angeles")
    private func cityName(from timeZoneIdentifier: String) -> String {
        let components = timeZoneIdentifier.split(separator: "/")
        let last = components.last.map(String.init) ?? timeZoneIdentifier
        return last.replacingOccurrences(of: "_", with: " ")
    }
}
