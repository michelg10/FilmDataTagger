//
//  LocationService.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import Foundation
import SwiftData
import CoreLocation

enum GeocodingState: Equatable {
    case disabled
    case notAuthorized
    case locating
    case geocoding(CLLocation)
    case timedOut(CLLocation?)
    case resolved(String, String?, CLLocation)

    /// The place name to persist to a LogItem, or nil if not ready.
    var persistablePlaceName: String? {
        if case .resolved(let name, _, _) = self { return name }
        return nil
    }

    /// The city name to persist to a LogItem, or nil if not ready.
    var persistableCityName: String? {
        if case .resolved(_, let city, _) = self { return city }
        return nil
    }

    /// Display text for the UI.
    var displayText: String {
        switch self {
        case .disabled: "Disabled"
        case .notAuthorized: "Disabled"
        case .locating: "Locating..."
        case .geocoding: "Locating..."
        case .timedOut: "Unavailable"
        case .resolved(let name, _, _): name
        }
    }

    /// Subtitle for the expanded capture sheet.
    var displaySubtext: String {
        switch self {
        case .disabled: "Location off"
        case .notAuthorized: "Location not allowed"
        case .locating: "Locating..."
        case .geocoding(let loc), .resolved(_, _, let loc):
            String(format: "%.4f / %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
        case .timedOut(let loc):
            loc.map { String(format: "%.4f / %.4f", $0.coordinate.latitude, $0.coordinate.longitude) }
                ?? "Location unavailable"
        }
    }
}

@Observable @MainActor
final class LocationService {
    private let locationManager = LocationManager()
    private var lastGeocodedLocation: CLLocation?
    nonisolated(unsafe) private var geocodeTask: Task<Void, Never>?

    var geocodingState: GeocodingState = .disabled
    var currentLocation: CLLocation? { locationManager.currentLocation }

    /// Brief fallback to prevent "Locating..." flash during re-geocoding.
    private(set) var fallbackPlaceName: String?
    private var fallbackID: UUID?

    /// Display-friendly place name: uses the real geocoded result, falling back briefly to the previous result during re-geocoding.
    var displayPlaceName: String? {
        geocodingState.persistablePlaceName ?? fallbackPlaceName
    }

    deinit {
        geocodeTask?.cancel()
    }

    func setup() {
        locationManager.onAuthorizationChanged = { [weak self] status in
            self?.handleAuthorizationChange(status)
        }

        guard AppSettings.shared.locationEnabled else {
            geocodingState = .disabled
            return
        }

        let status = locationManager.authorizationStatus
        if status == .denied || status == .restricted {
            geocodingState = .notAuthorized
        } else {
            geocodingState = .locating
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationManager.startUpdating()
            } else {
                locationManager.requestPermission()
            }
            startLiveGeocoding()
        }
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard AppSettings.shared.locationEnabled else { return }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdating()
            if case .notAuthorized = geocodingState {
                geocodingState = .locating
                startLiveGeocoding()
            }
        case .denied, .restricted:
            geocodeTask?.cancel()
            geocodeTask = nil
            locationManager.stopUpdating()
            lastGeocodedLocation = nil
            geocodingState = .notAuthorized
        default:
            break
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            let status = locationManager.authorizationStatus
            if status == .denied || status == .restricted {
                geocodingState = .notAuthorized
            } else {
                geocodingState = .locating
                locationManager.requestPermission()
                locationManager.startUpdating()
                startLiveGeocoding()
            }
        } else {
            geocodeTask?.cancel()
            geocodeTask = nil
            locationManager.stopUpdating()
            geocodingState = .disabled
            lastGeocodedLocation = nil
        }
    }

    func updateAccuracy(_ accuracy: CLLocationAccuracy) {
        locationManager.updateAccuracy(accuracy)
    }

    /// Backfill place names for recent items that were logged without geocoding.
    /// Geocoding runs off-main; results are delivered via callback for the caller to write to its own context.
    func geocodeRecentItems(container: ModelContainer, since cutoffDate: Date, onComplete: @MainActor @Sendable @escaping ([(UUID, GeocodingResult)]) -> Void) {
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

            var geocoded: [(UUID, GeocodingResult)] = []
            for (id, location) in pending {
                guard !Task.isCancelled else { break }
                let result = await Geocoder.geocode(location)
                if result.placeName != nil || result.cityName != nil {
                    geocoded.append((id, result))
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let results = geocoded
            await MainActor.run { onComplete(results) }
        }
    }

    // MARK: - Live Geocoding

    private func startLiveGeocoding() {
        geocodeTask = Task {
            // Time out after 15s if we still have no location.
            let parentTask = geocodeTask
            Task {
                try? await Task.sleep(for: .seconds(15))
                guard parentTask?.isCancelled != true else { return }
                if case .locating = geocodingState {
                    geocodingState = .timedOut(nil)
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let location = locationManager.currentLocation else { continue }
                // Only re-geocode if moved >50m from last geocoded spot
                if let last = lastGeocodedLocation, location.distance(from: last) < 50 { continue }
                lastGeocodedLocation = location

                // Stash current place name as fallback to prevent UI flash during re-geocode
                if let currentName = geocodingState.persistablePlaceName {
                    let id = UUID()
                    fallbackPlaceName = currentName
                    fallbackID = id
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        if self.fallbackID == id {
                            self.fallbackPlaceName = nil
                            self.fallbackID = nil
                        }
                    }
                }

                geocodingState = .geocoding(location)
                let geo = await Geocoder.geocode(location)
                if let name = geo.placeName {
                    geocodingState = .resolved(name, geo.cityName, location)
                } else {
                    geocodingState = .timedOut(location)
                }
                // Clear fallback once we have a real result
                fallbackPlaceName = nil
                fallbackID = nil
            }
        }
    }
}
