//
//  LogItem.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class LogItem {
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

    /// The time zone identifier at the time of capture (e.g., "America/Los_Angeles")
    var timeZoneIdentifier: String?

    /// When true, this item is a placeholder with no captured metadata
    var isPlaceholder: Bool = false

    /// Reference photo captured at time of logging (JPEG data, stored externally by SwiftData)
    @Attribute(.externalStorage) var photoData: Data?

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
}
