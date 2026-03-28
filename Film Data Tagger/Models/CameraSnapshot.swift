//
//  CameraSnapshot.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/27/26.
//

import Foundation

struct CameraSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var listOrder: Double
    var rollCount: Int
    var totalExposureCount: Int
    var lastUsedDate: Date?
    var activeFilmStock: String?
    var activeExposureCount: Int?
    var activeCapacity: Int?
}
