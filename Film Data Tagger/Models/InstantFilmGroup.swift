//
//  InstantFilmGroup.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

import Foundation
import SwiftData

@Model
final class InstantFilmGroup {
    var id: UUID = UUID()
    var name: String = "SystemReserved:DataError"
    var createdAt: Date = Date.distantPast
    /// User-defined ordering in the camera list.
    var listOrder: Double = 0

    /// The sub-cameras in this group (e.g., "Polaroid 600", "SX-70")
    @Relationship(deleteRule: .cascade, inverse: \InstantFilmCamera.group)
    var cameras: [InstantFilmCamera]?

    init(name: String, listOrder: Double = 0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.listOrder = listOrder
    }
}
