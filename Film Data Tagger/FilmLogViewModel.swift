//
//  FilmLogViewModel.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftUI
import SwiftData
import CoreLocation

@Observable
@MainActor
final class FilmLogViewModel {
    private let modelContext: ModelContext
    private let locationManager = LocationManager()

    private static let lastLaunchKey = "lastAppLaunchDate"

    var activeRoll: Roll?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Setup

    func setup() {
        locationManager.requestPermission()
        loadOrCreateActiveRoll()
        geocodeRecentUngeocodedItems()
        recordAppLaunch()
    }

    private func recordAppLaunch() {
        UserDefaults.standard.set(Date(), forKey: Self.lastLaunchKey)
    }

    private var lastAppLaunch: Date? {
        UserDefaults.standard.object(forKey: Self.lastLaunchKey) as? Date
    }

    private func loadOrCreateActiveRoll() {
        let descriptor = FetchDescriptor<Roll>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            let rolls = try modelContext.fetch(descriptor)
            if let existingRoll = rolls.first {
                activeRoll = existingRoll
            } else {
                createDefaultRoll()
            }
        } catch {
            print("Failed to fetch rolls: \(error)")
            createDefaultRoll()
        }
    }

    private func createDefaultRoll() {
        let camera = Camera(name: "Test Camera")
        modelContext.insert(camera)

        let roll = Roll(filmStock: "Kodak Portra 400", camera: camera)
        modelContext.insert(roll)

        activeRoll = roll
    }

    // MARK: - Logging

    func logExposure() {
        guard let roll = activeRoll else { return }

        let item = LogItem(roll: roll)
        let location = locationManager.currentLocation

        if let location = location {
            item.setLocation(location)
        }

        modelContext.insert(item)
        roll.logItems.append(item)
        roll.touch()

        // Geocode in background
        if let location = location {
            Task {
                item.placeName = await Geocoder.placeName(for: location)
            }
        }
    }

    var canLogExposure: Bool {
        activeRoll != nil
    }

    // MARK: - Geocoding

    private func geocodeRecentUngeocodedItems() {
        Task {
            // Geocode items since the earlier of: last 7 days OR last app launch
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let cutoffDate = min(sevenDaysAgo, lastAppLaunch ?? Date.distantPast)

            let descriptor = FetchDescriptor<LogItem>(
                predicate: #Predicate<LogItem> { $0.deletedAt == nil }
            )

            do {
                let allItems = try modelContext.fetch(descriptor)
                let itemsToGeocode = allItems.filter { item in
                    item.placeName == nil &&
                    item.latitude != nil &&
                    item.longitude != nil &&
                    item.createdAt >= cutoffDate
                }

                for item in itemsToGeocode {
                    guard let lat = item.latitude, let lon = item.longitude else { continue }
                    let location = CLLocation(latitude: lat, longitude: lon)
                    item.placeName = await Geocoder.placeName(for: location)
                    // Small delay to avoid rate limiting
                    try? await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                print("Failed to fetch items for geocoding: \(error)")
            }
        }
    }

    // MARK: - Queries

    func fetchLogItems() throws -> [LogItem] {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
