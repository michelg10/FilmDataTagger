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
        guard AppSettings.shared.locationEnabled else { return }
        locationManager.requestPermission()
        startLiveGeocoding()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            locationManager.requestPermission()
            locationManager.startUpdating()
            startLiveGeocoding()
        } else {
            geocodeTask?.cancel()
            geocodeTask = nil
            locationManager.stopUpdating()
            currentPlaceName = nil
            lastGeocodedLocation = nil
        }
    }

    func updateAccuracy(_ accuracy: CLLocationAccuracy) {
        locationManager.updateAccuracy(accuracy)
    }

    /// Backfill place names for recent items that were logged without geocoding.
    func geocodeRecentItems(modelContext: ModelContext, since cutoffDate: Date) {
        // Fetch on main (ModelContext requires it), collect IDs + coordinates
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> {
                $0.placeName == nil &&
                $0.latitude != nil &&
                $0.longitude != nil &&
                $0.createdAt >= cutoffDate
            }
        )

        let pending: [(UUID, CLLocation)]
        do {
            let items = try modelContext.fetch(descriptor)
            pending = items.compactMap { item in
                guard let lat = item.latitude, let lon = item.longitude else { return nil }
                return (item.id, CLLocation(latitude: lat, longitude: lon))
            }
        } catch {
            print("Failed to fetch items for geocoding: \(error)")
            return
        }

        guard !pending.isEmpty else { return }

        // Geocode off main, then hop back to assign results
        Task.detached {
            for (id, location) in pending {
                let placeName = await Geocoder.placeName(for: location)
                await MainActor.run {
                    let lookup = FetchDescriptor<LogItem>(predicate: #Predicate { $0.id == id })
                    if let item = try? modelContext.fetch(lookup).first {
                        item.placeName = placeName
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
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
