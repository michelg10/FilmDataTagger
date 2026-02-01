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

    /// Frame number on the roll (optional, user can set this)
    var frameNumber: Int?

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

    init(roll: Roll, frameNumber: Int? = nil, camera: Camera? = nil) {
        self.id = UUID()
        self.roll = roll
        self.frameNumber = frameNumber
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
