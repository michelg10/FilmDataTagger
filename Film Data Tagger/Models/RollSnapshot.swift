//
//  RollSnapshot.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/27/26.
//

import Foundation

struct RollSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    var cameraID: UUID?
    var filmStock: String
    var capacity: Int
    var extraExposures: Int
    var isActive: Bool
    var createdAt: Date
    var lastExposureDate: Date?
    var exposureCount: Int
    var totalCapacity: Int
}
