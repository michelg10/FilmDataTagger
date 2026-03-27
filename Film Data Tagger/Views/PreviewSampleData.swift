//
//  PreviewSampleData.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/9/26.
//

import SwiftUI
import SwiftData

/// Shared sample data for SwiftUI previews
enum PreviewSampleData {
    struct FakeExposure {
        let lat: Double
        let lon: Double
        let placeName: String
        let minutesAgo: Int
        let notes: String?
    }

    static let exposures: [FakeExposure] = [
        .init(lat: 34.0037, lon: -118.4810, placeName: "Dockweiler State Beach", minutesAgo: 5, notes: nil),
        .init(lat: 34.0195, lon: -118.4912, placeName: "Venice Beach Boardwalk", minutesAgo: 28, notes: "Golden hour light"),
        .init(lat: 34.0259, lon: -118.5100, placeName: "Santa Monica Pier", minutesAgo: 45, notes: nil),
        .init(lat: 34.0522, lon: -118.2437, placeName: "Grand Central Market, Los Angeles", minutesAgo: 120, notes: "Neon signs"),
        .init(lat: 34.1184, lon: -118.3004, placeName: "Griffith Observatory", minutesAgo: 180, notes: nil),
        .init(lat: 34.0407, lon: -118.2468, placeName: "Arts District, Los Angeles", minutesAgo: 240, notes: "Street mural"),
        .init(lat: 34.0669, lon: -118.3495, placeName: "The Grove", minutesAgo: 300, notes: nil),
    ]

    /// Creates an in-memory container populated with sample data
    @MainActor
    static func makeContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: Camera.self, Roll.self, LogItem.self, InstantFilmGroup.self, InstantFilmCamera.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let camera = Camera(name: "Leica M6")
        context.insert(camera)

        let roll = Roll(filmStock: "Kodak Portra 400", camera: camera)
        context.insert(roll)

        for exposure in exposures {
            let item = LogItem(roll: roll)
            item.createdAt = Date().addingTimeInterval(TimeInterval(-exposure.minutesAgo * 60))
            item.latitude = exposure.lat
            item.longitude = exposure.lon
            item.placeName = exposure.placeName
            item.notes = exposure.notes
            context.insert(item)
        }

        return container
    }

    /// Returns the sample log items from a container
    @MainActor
    static func sampleItems(from container: ModelContainer) -> [LogItem] {
        let descriptor = FetchDescriptor<LogItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
}
