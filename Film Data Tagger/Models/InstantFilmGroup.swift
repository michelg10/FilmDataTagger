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
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    /// When non-nil, this group has been soft-deleted
    var deletedAt: Date?

    /// The sub-cameras in this group (e.g., "Polaroid 600", "SX-70")
    @Relationship(deleteRule: .cascade, inverse: \InstantFilmCamera.group)
    var cameras: [InstantFilmCamera] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.deletedAt = nil
    }

    func softDelete() {
        self.deletedAt = Date()
    }

    func restore() {
        self.deletedAt = nil
    }

    var isDeleted: Bool {
        deletedAt != nil
    }
}
