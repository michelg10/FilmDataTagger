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
    func geocodeRecentItems(container: ModelContainer, since cutoffDate: Date) {
        Task.detached {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<LogItem>(
                predicate: #Predicate<LogItem> {
                    $0.placeName == nil &&
                    $0.latitude != nil &&
                    $0.longitude != nil &&
                    $0.createdAt >= cutoffDate
                }
            )

            let items = (try? context.fetch(descriptor)) ?? []
            let pending = items.compactMap { item -> (UUID, CLLocation)? in
                guard let lat = item.latitude, let lon = item.longitude else { return nil }
                return (item.id, CLLocation(latitude: lat, longitude: lon))
            }

            for (id, location) in pending {
                guard !Task.isCancelled else { break }
                let placeName = await Geocoder.placeName(for: location)
                let lookup = FetchDescriptor<LogItem>(predicate: #Predicate { $0.id == id })
                if let item = try? context.fetch(lookup).first {
                    item.placeName = placeName
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? context.save()
        }
    }

    // MARK: - Live Geocoding

    private func startLiveGeocoding() {
        geocodeTask = Task {
            // Show "Unknown" after 15s if we still have no location.
            // Captures the parent task so we can check its cancellation.
            let parentTask = geocodeTask
            Task {
                try? await Task.sleep(for: .seconds(15))
                guard parentTask?.isCancelled != true else { return }
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
