//
//  Roll.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftData

@Model
final class Roll {
    @Attribute(.unique) var id: UUID

    /// The camera used for this roll (nil in instant film mode where each LogItem has its own camera)
    var camera: Camera?

    /// Film stock name (e.g., "Portra 400", "HP5+", "Instax Mini")
    var filmStock: String

    /// When true, this roll is unbounded and each LogItem can have its own camera
    var isInstantFilmMode: Bool

    var createdAt: Date
    var modifiedAt: Date

    /// When non-nil, this roll has been soft-deleted
    var deletedAt: Date?

    /// The log items (frames) in this roll
    @Relationship(deleteRule: .cascade, inverse: \LogItem.roll)
    var logItems: [LogItem] = []

    init(filmStock: String, camera: Camera? = nil, isInstantFilmMode: Bool = false) {
        self.id = UUID()
        self.filmStock = filmStock
        self.camera = camera
        self.isInstantFilmMode = isInstantFilmMode
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.deletedAt = nil
    }

    /// Call this whenever the roll is modified
    func touch() {
        self.modifiedAt = Date()
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
