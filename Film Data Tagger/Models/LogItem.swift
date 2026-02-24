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

    /// When true, this item is a placeholder with no captured metadata
    var isPlaceholder: Bool = false

    /// Reference photo captured at time of logging (JPEG data, stored externally by SwiftData)
    @Attribute(.externalStorage) var photoData: Data?

    init(roll: Roll) {
        self.id = UUID()
        self.roll = roll
        self.createdAt = Date()
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

    /// Whether this item is a pre-first-frame exposure
    var isPreFrame: Bool {
        guard let roll = roll else { return false }
        let sortedItems = (roll.logItems ?? []).sorted { $0.createdAt < $1.createdAt }
        guard let index = sortedItems.firstIndex(where: { $0.id == self.id }) else { return false }
        return index < roll.extraExposures
    }

    /// Frame number computed from position in roll (1-indexed, offset by extraExposures), or nil if not in a roll
    var frameNumber: Int? {
        guard let roll = roll else { return nil }
        let sortedItems = (roll.logItems ?? []).sorted { $0.createdAt < $1.createdAt }
        guard let index = sortedItems.firstIndex(where: { $0.id == self.id }) else { return nil }
        if index < roll.extraExposures { return nil }
        return index - roll.extraExposures + 1
    }
}
