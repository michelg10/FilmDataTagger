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

/// Distinguishes regular captured exposures from manually-positioned markers
/// (placeholders, lost frames). Stored on `LogItem` as a raw string via `exposureTypeRaw`
/// for CloudKit compatibility
nonisolated enum ExposureType: Equatable, Hashable, Sendable {
    case regular
    case placeholder
    case lostFrame
    /// Forward-compat for cases written by newer clients we don't recognize yet.
    case unknown(String)

    var rawValue: String {
        switch self {
        case .regular:        "regular"
        case .placeholder:    "placeholder"
        case .lostFrame:      "lostFrame"
        case .unknown(let v): v
        }
    }

    init(_ rawValue: String) {
        switch rawValue {
        case "regular":     self = .regular
        case "placeholder": self = .placeholder
        case "lostFrame":   self = .lostFrame
        default:            self = .unknown(rawValue)
        }
    }

    /// True for placeholder + lostFrame — the "no captured metadata, hand-positioned" family.
    /// Drag/sort/no-metadata-display logic should branch on this, not on the specific case.
    var isPlaceholderLike: Bool {
        switch self {
        case .placeholder, .lostFrame: true
        case .regular, .unknown:       false
        }
    }
}

extension ExposureType: Codable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExposureType(raw)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
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

    /// LEGACY (read-only since 1.1): used as a fallback when `exposureTypeRaw == nil`
    /// for rows pushed by 1.0.x CloudKit clients that don't know about `exposureTypeRaw`.
    /// 1.1+ never writes to this field; new rows leave it at the default `false`.
    /// Do not use directly — use `exposureType` instead.
    var isPlaceholder: Bool = false

    /// Raw storage for `exposureType` (regular / placeholder / lostFrame).
    /// Optional with `nil` default so SwiftData lightweight-migrates legacy rows automatically.
    /// Resolved via the `exposureType` accessor, which falls back to `isPlaceholder` when nil.
    var exposureTypeRaw: String?

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

    /// Typed accessor for `exposureTypeRaw`. Reads fall back to the legacy `isPlaceholder`
    /// field when the raw value is nil (CloudKit drift from 1.0.x clients, or pre-backfill rows).
    /// Writes only touch `exposureTypeRaw` — `isPlaceholder` stays at its default forever.
    @Transient var exposureType: ExposureType {
        get {
            if let raw = exposureTypeRaw { return ExposureType(raw) }
            return isPlaceholder ? .placeholder : .regular
        }
        set { exposureTypeRaw = newValue.rawValue }
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
        self.exposureTypeRaw = ExposureType.regular.rawValue
    }

    /// Create a placeholder exposure (no metadata captured)
    static func placeholder(roll: Roll) -> LogItem {
        let item = LogItem(roll: roll)
        item.exposureType = .placeholder
        item.hasRealCreatedAt = false
        return item
    }

    /// Create a lost-frame marker (frame was exposed but the data is gone —
    /// double-exposure mishap, light leak, given-away Polaroid, etc.).
    /// Functionally identical to `placeholder` for sort/drag/no-metadata purposes,
    /// but distinguished for display.
    static func lostFrame(roll: Roll) -> LogItem {
        let item = LogItem(roll: roll)
        item.exposureType = .lostFrame
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

    func snapshot(formatters: SnapshotDateFormatters) -> LogItemSnapshot {
        let (capturedTZ, hasDifferentTZ, capturedTZLabel) = formatters.timeZoneInfo(for: createdAt, tzIdentifier: timeZoneIdentifier, cityName: cityName)
        let (capTimeFmt, capDateFmt) = formatters.captured(for: capturedTZ)

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
            exposureType: exposureType,
            source: source,
            hasThumbnail: cachedHasThumbnail,
            hasPhoto: cachedHasPhoto,
            formattedTime: createdAt.formatted(capTimeFmt),
            formattedDate: createdAt.formatted(capDateFmt),
            localFormattedTime: createdAt.formatted(formatters.localTime),
            localFormattedDate: createdAt.formatted(formatters.localDate),
            hasDifferentTimeZone: hasDifferentTZ,
            capturedTZLabel: capturedTZLabel
        )
    }

    /// Convenience for single-item snapshots (e.g. previews) where formatter
    /// reuse doesn't matter.
    var snapshot: LogItemSnapshot {
        snapshot(formatters: SnapshotDateFormatters())
    }
}
