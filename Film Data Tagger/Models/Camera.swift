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
    var id: UUID = UUID()
    var name: String = "SystemReserved:DataError"
    var createdAt: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \Roll.camera)
    var rolls: [Roll]?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
