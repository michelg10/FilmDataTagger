//
//  RollSnapshot.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/27/26.
//

import Foundation

struct RollSnapshot: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var cameraID: UUID?
    var filmStock: String
    var capacity: Int
    var extraExposures: Int
    var isActive: Bool
    var loadedAt: Date
    var loadedTimeZoneIdentifier: String?
    var loadedCityName: String?
    var unloadedAt: Date?
    var unloadedTimeZoneIdentifier: String?
    var unloadedCityName: String?
    var notes: String?
    var lastExposureDate: Date?
    var exposureCount: Int
    var totalCapacity: Int
}
