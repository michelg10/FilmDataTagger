//
//  SchemaVersioning.swift
//  Film Data Tagger
//

import SwiftData

/// V1 captures the schema as of the initial versioned release.
/// All models are defined in their own files — this enum just declares
/// the version and lists the model types for the migration plan.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Camera.self,
            Roll.self,
            LogItem.self,
        ]
    }
}

enum FilmDataTaggerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet — V1 is the baseline
        []
    }
}
