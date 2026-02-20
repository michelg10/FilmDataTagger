//
//  InstantFilmCamera.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

import Foundation
import SwiftData

@Model
final class InstantFilmCamera {
    @Attribute(.unique) var id: UUID
    var name: String

    /// Number of frames per film pack (e.g., 8 for Polaroid 600)
    var packCapacity: Int

    var createdAt: Date

    /// When non-nil, this camera has been soft-deleted
    var deletedAt: Date?

    /// The instant film group this camera belongs to
    var group: InstantFilmGroup?

    /// Film packs (rolls) for this camera
    @Relationship(deleteRule: .cascade, inverse: \Roll.instantFilmCamera)
    var rolls: [Roll] = []

    init(name: String, packCapacity: Int, group: InstantFilmGroup) {
        self.id = UUID()
        self.name = name
        self.packCapacity = packCapacity
        self.group = group
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
