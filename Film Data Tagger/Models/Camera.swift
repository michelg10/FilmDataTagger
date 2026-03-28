//
//  Camera.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftData

@Model
final class Camera {
    #Index<Camera>([\.id])

    var id: UUID = UUID()
    var name: String = "SystemReserved:DataError"
    var createdAt: Date = Date.distantPast
    /// User-defined ordering in the camera list.
    var listOrder: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \Roll.camera)
    var rolls: [Roll]?

    // MARK: - Cached summaries (maintained by ViewModel to avoid faulting `rolls` in view bodies)

    var cachedRollCount: Int = 0
    var cachedTotalExposureCount: Int = 0
    var cachedLastUsedDate: Date?
    var cachedActiveFilmStock: String?
    var cachedActiveExposureCount: Int?
    var cachedActiveCapacity: Int?

    init(name: String, listOrder: Double = 0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.listOrder = listOrder
    }

    // MARK: - Snapshot

    var snapshot: CameraSnapshot {
        CameraSnapshot(
            id: id,
            name: name,
            createdAt: createdAt,
            listOrder: listOrder,
            rollCount: cachedRollCount,
            totalExposureCount: cachedTotalExposureCount,
            lastUsedDate: cachedLastUsedDate,
            activeFilmStock: cachedActiveFilmStock,
            activeExposureCount: cachedActiveExposureCount,
            activeCapacity: cachedActiveCapacity
        )
    }
}
