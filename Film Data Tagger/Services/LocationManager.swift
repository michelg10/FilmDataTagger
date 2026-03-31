//
//  LocationManager.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import CoreLocation

@Observable @MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus
    var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = AppSettings.shared.locationAccuracy.clAccuracy
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func updateAccuracy(_ accuracy: CLLocationAccuracy) {
        manager.desiredAccuracy = accuracy
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        currentLocation = nil
    }

    func startUpdating() {
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task(priority: .medium) { @MainActor in
            self.currentLocation = location
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task(priority: .medium) { @MainActor in
            self.authorizationStatus = status
            self.onAuthorizationChanged?(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        debugLog("Location error: \(error.localizedDescription)")
    }
}
