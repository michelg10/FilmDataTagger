//
//  LocationService.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import Foundation
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
        case .notAuthorized: "Not allowed"
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
        case .notAuthorized: "No location access"
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
    /// True when location is enabled but the user hasn't been prompted yet.
    private(set) var needsPermission = false
    var currentLocation: CLLocation? { locationManager.currentLocation }

    /// Brief fallback to prevent "Locating..." flash during re-geocoding.
    private(set) var fallbackPlaceName: String?
    private var fallbackID: UUID?

    /// Display-friendly place name: uses the real geocoded result, falling back briefly to the previous result during re-geocoding.
    var displayPlaceName: String? {
        geocodingState.persistablePlaceName ?? fallbackPlaceName
    }

    /// Display-ready location text for the UI.
    var displayLocationText: String {
        displayPlaceName ?? geocodingState.displayText
    }

    /// Display-ready location subtext (coordinates or status).
    var displayLocationSubtext: String {
        geocodingState.displaySubtext
    }

    deinit {
        geocodeTask?.cancel()
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil {
            assertionFailure("LocationService should never be deallocated")
        }
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
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            geocodingState = .locating
            locationManager.startUpdating()
            startLiveGeocoding()
        } else if status == .notDetermined {
            needsPermission = true
        }
    }

    /// Request location permission if not yet determined. Call when the user
    /// starts a permission prompt flow
    func requestPermissionIfNeeded() {
        guard AppSettings.shared.locationEnabled else { return }
        let status = locationManager.authorizationStatus
        guard status == .notDetermined else { return }
        needsPermission = false
        geocodingState = .locating
        locationManager.requestPermission()
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard AppSettings.shared.locationEnabled else { return }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            needsPermission = false
            locationManager.startUpdating()
            if geocodeTask == nil {
                geocodingState = .locating
                startLiveGeocoding()
            }
        case .denied, .restricted:
            needsPermission = false
            geocodeTask?.cancel()
            geocodeTask = nil
            locationManager.stopUpdating()
            lastGeocodedLocation = nil
            fallbackPlaceName = nil
            fallbackID = nil
            geocodingState = .notAuthorized
        default:
            break
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            let status = locationManager.authorizationStatus
            if status == .denied || status == .restricted {
                needsPermission = false
                geocodingState = .notAuthorized
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                needsPermission = false
                geocodingState = .locating
                locationManager.startUpdating()
                startLiveGeocoding()
            } else {
                needsPermission = true
            }
        } else {
            needsPermission = false
            geocodeTask?.cancel()
            geocodeTask = nil
            locationManager.stopUpdating()
            geocodingState = .disabled
            lastGeocodedLocation = nil
            fallbackPlaceName = nil
            fallbackID = nil
        }
    }

    func updateAccuracy(_ accuracy: CLLocationAccuracy) {
        locationManager.updateAccuracy(accuracy)
    }

    // MARK: - Live Geocoding

    /// Start the live geocoding loop. Cancels any existing loop first.
    /// Spawns child tasks (timeout, fallback clear, geocoding indicator).
    /// The main loop checks Task.isCancelled after every await to avoid writing stale state.
    private func startLiveGeocoding() {
        geocodeTask?.cancel()
        geocodeTask = Task(priority: .medium) {
            // Time out after 15s if we still have no location.
            let parentTask = geocodeTask
            Task(priority: .medium) {
                try? await Task.sleep(for: .seconds(15))
                guard parentTask?.isCancelled != true else { return }
                if case .locating = geocodingState {
                    debugLog("Location timed out after 15s — no location received")
                    geocodingState = .timedOut(nil)
                }
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let location = locationManager.currentLocation else { continue }
                // Only re-geocode if moved beyond the accuracy-based threshold
                let threshold = AppSettings.shared.locationAccuracy.geocodeDistanceThreshold
                if let last = lastGeocodedLocation, location.distance(from: last) < threshold { continue }

                // Stash current place name as fallback to prevent UI flash during re-geocode
                if let currentName = geocodingState.persistablePlaceName {
                    let id = UUID()
                    fallbackPlaceName = currentName
                    fallbackID = id
                    Task(priority: .medium) {
                        try? await Task.sleep(for: .seconds(1))
                        if self.fallbackID == id {
                            self.fallbackPlaceName = nil
                            self.fallbackID = nil
                        }
                    }
                }

                // Only show "Locating..." if the geocode takes longer than 0.3s,
                // to avoid flashing when retrying quickly (e.g., no internet).
                let geocodingIndicator = Task(priority: .medium) { [parentTask] in
                    try? await Task.sleep(for: .seconds(0.3))
                    guard !Task.isCancelled, parentTask?.isCancelled != true else { return }
                    self.geocodingState = .geocoding(location)
                }
                let geo = await Geocoder.geocode(location)
                geocodingIndicator.cancel()
                guard !Task.isCancelled else { break }
                if let name = geo.placeName {
                    lastGeocodedLocation = location
                    geocodingState = .resolved(name, geo.cityName, location)
                } else {
                    debugLog("Geocoding returned nil for \(String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude))")
                    geocodingState = .timedOut(location)
                }
                // Clear fallback once we have a real result
                fallbackPlaceName = nil
                fallbackID = nil
            }
        }
    }
}
