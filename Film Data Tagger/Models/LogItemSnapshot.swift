//
//  LogItemSnapshot.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/27/26.
//

import Foundation

struct LogItemSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    var createdAt: Date
    var hasRealCreatedAt: Bool
    var notes: String?
    // Location
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var cityName: String?
    var timeZoneIdentifier: String?
    // State
    var isPlaceholder: Bool
    var source: String?
    // Media (thumbnails loaded via ImageCache, not carried in the snapshot)
    var hasThumbnail: Bool
    var hasPhoto: Bool
    // Pre-formatted display strings
    var formattedTime: String
    var formattedDate: String
    var formattedTimeForeignTZ: String?
    var formattedDateForeignTZ: String?
    var formattedTimeLocal: String?
    var formattedDateLocal: String?
}
