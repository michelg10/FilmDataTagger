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

    init(name: String, listOrder: Double = 0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.listOrder = listOrder
    }
}
