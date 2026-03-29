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
    // Time display — all pre-computed by the DataStore.
    /// Capture timezone (immutable — never recomputed).
    var formattedTime: String
    var formattedDate: String
    /// Device timezone (recomputed by DataStore if device TZ changes).
    var localFormattedTime: String
    var localFormattedDate: String
    /// Whether the capture TZ differs from the device TZ (recomputed on TZ change).
    var hasDifferentTimeZone: Bool
    /// Human-readable capture TZ label (e.g., "Tokyo"). Uses cityName if available.
    var capturedTZLabel: String?
}
