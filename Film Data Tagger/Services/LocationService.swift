//
//  LocationService.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import Foundation
import SwiftData
import CoreLocation

@Observable @MainActor
final class LocationService {
    private let locationManager = LocationManager()
    private var lastGeocodedLocation: CLLocation?
    nonisolated(unsafe) private var geocodeTask: Task<Void, Never>?

    var currentPlaceName: String?
    var currentLocation: CLLocation? { locationManager.currentLocation }

    deinit {
        geocodeTask?.cancel()
    }

    func setup() {
        locationManager.requestPermission()
        startLiveGeocoding()
    }

    /// Backfill place names for recent items that were logged without geocoding.
    func geocodeRecentItems(modelContext: ModelContext, since cutoffDate: Date) {
        Task {
            let descriptor = FetchDescriptor<LogItem>()

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

    // MARK: - Live Geocoding

    private func startLiveGeocoding() {
        geocodeTask = Task {
            // Show "Unknown" after 15s if we still have no location
            Task {
                try? await Task.sleep(for: .seconds(15))
                if currentPlaceName == nil {
                    currentPlaceName = "Unknown"
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let location = locationManager.currentLocation else { continue }
                // Only re-geocode if moved >50m from last geocoded spot
                if let last = lastGeocodedLocation, location.distance(from: last) < 50 { continue }
                lastGeocodedLocation = location
                currentPlaceName = await Geocoder.placeName(for: location)
            }
        }
    }
}
