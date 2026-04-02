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

    init(name: String, listOrder: Double = 0, createdAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.listOrder = listOrder
    }

    /// The currently active roll. Faults the rolls relationship — avoid calling from view bodies.
    var activeRoll: Roll? {
        (rolls ?? []).first(where: \.isActive)
    }

    // MARK: - Snapshot (camera's own fields only — derived data computed by loadAll)

    var snapshot: CameraSnapshot {
        CameraSnapshot(
            id: id,
            name: name,
            createdAt: createdAt,
            listOrder: listOrder,
            rollCount: 0,
            totalExposureCount: 0
        )
    }
}
