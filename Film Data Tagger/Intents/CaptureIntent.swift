//
//  CaptureIntent.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import AppIntents
import SwiftData
import CoreLocation

struct LogExposureIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Exposure"
    static var description = IntentDescription("Log a new exposure with current location and timestamp")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let container = try ModelContainer(for: Camera.self, Roll.self, LogItem.self, InstantFilmGroup.self, InstantFilmCamera.self)
        let context = container.mainContext

        // Find or create active roll
        let rollDescriptor = FetchDescriptor<Roll>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        let rolls = try context.fetch(rollDescriptor)

        let roll: Roll
        if let existingRoll = rolls.first {
            roll = existingRoll
        } else {
            // Create default camera and roll if none exist
            let camera = Camera(name: "Default Camera")
            context.insert(camera)
            roll = Roll(filmStock: "Unknown Film", camera: camera)
            context.insert(roll)
        }

        // Create the log item
        let item = LogItem(roll: roll)

        // Try to get location (geocoding happens on next app launch)
        let location = await getCurrentLocation()
        if let location = location {
            item.setLocation(location)
        }

        context.insert(item)
        roll.logItems.append(item)
        roll.touch()

        try context.save()

        let exposureCount = roll.logItems.count
        let locationStatus = item.hasLocation ? "with location" : "without location"

        return .result(value: "Logged exposure #\(exposureCount) \(locationStatus)")
    }

    @MainActor
    private func getCurrentLocation() async -> CLLocation? {
        let manager = CLLocationManager()

        // Check authorization
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let delegate = OneTimeLocationDelegate { location in
                continuation.resume(returning: location)
            }
            manager.delegate = delegate
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.requestLocation()

            // Store delegate to prevent deallocation
            objc_setAssociatedObject(manager, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

@MainActor
private class OneTimeLocationDelegate: NSObject, CLLocationManagerDelegate {
    private let completion: (CLLocation?) -> Void
    private var hasCompleted = false

    init(completion: @escaping (CLLocation?) -> Void) {
        self.completion = completion
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            guard !self.hasCompleted else { return }
            self.hasCompleted = true
            self.completion(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard !self.hasCompleted else { return }
            self.hasCompleted = true
            self.completion(nil)
        }
    }
}

struct FilmDataTaggerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExposureIntent(),
            phrases: [
                "Log exposure in \(.applicationName)",
                "Log shot in \(.applicationName)",
                "New exposure in \(.applicationName)"
            ],
            shortTitle: "Log Exposure",
            systemImageName: "camera.shutter.button.fill"
        )
    }
}
