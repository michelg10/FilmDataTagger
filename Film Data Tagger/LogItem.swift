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
    @Attribute(.unique) var id: UUID

    /// The roll this item belongs to
    var roll: Roll?

    /// Camera used for this specific shot (used in instant film mode)
    var camera: Camera?

    var createdAt: Date

    /// When non-nil, this item has been soft-deleted (but data is preserved for sync safety)
    var deletedAt: Date?

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

    init(roll: Roll, camera: Camera? = nil) {
        self.id = UUID()
        self.roll = roll
        self.camera = camera
        self.createdAt = Date()
        self.deletedAt = nil
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

    /// Frame number computed from position in roll (1-indexed), or nil if not in a roll
    var frameNumber: Int? {
        guard let roll = roll else { return nil }
        let activeItems = roll.logItems
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
        guard let index = activeItems.firstIndex(where: { $0.id == self.id }) else { return nil }
        return index + 1
    }

    /// Soft-delete this item (preserves data for iCloud sync safety)
    func softDelete() {
        self.deletedAt = Date()
    }

    /// Restore a soft-deleted item
    func restore() {
        self.deletedAt = nil
    }

    var isDeleted: Bool {
        deletedAt != nil
    }
}
