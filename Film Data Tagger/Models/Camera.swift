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
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    /// When non-nil, this camera has been soft-deleted
    var deletedAt: Date?

    // Inverse relationships
    @Relationship(deleteRule: .nullify, inverse: \Roll.camera)
    var rolls: [Roll] = []

    @Relationship(deleteRule: .nullify, inverse: \LogItem.camera)
    var logItems: [LogItem] = []

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
