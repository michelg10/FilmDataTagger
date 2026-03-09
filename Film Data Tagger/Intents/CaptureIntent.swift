//
//  CaptureIntent.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import AppIntents
import SwiftData
import CoreLocation

// MARK: - Camera App Entity

struct CameraEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Camera")
    static var defaultQuery = CameraEntityQuery()

    var id: UUID
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct CameraEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CameraEntity] {
        let context = Self.makeContext()
        let cameras = try context.fetch(FetchDescriptor<Camera>())
        return cameras
            .filter { identifiers.contains($0.id) }
            .compactMap { camera in
                guard let roll = camera.activeRoll else { return nil }
                return CameraEntity(id: camera.id, name: camera.name, subtitle: Self.subtitle(for: roll))
            }
    }

    @MainActor
    func suggestedEntities() async throws -> [CameraEntity] {
        let context = Self.makeContext()
        let cameras = try context.fetch(FetchDescriptor<Camera>())
        return cameras.compactMap { camera in
            guard let roll = camera.activeRoll else { return nil }
            return CameraEntity(id: camera.id, name: camera.name, subtitle: Self.subtitle(for: roll))
        }
    }

    @MainActor
    private static func makeContext() -> ModelContext {
        SharedModelContainer.shared.mainContext
    }

    private static func subtitle(for roll: Roll) -> String {
        let count = (roll.logItems ?? []).count
        let total = roll.totalCapacity
        var result = "\(count + 1) / \(total)" // show the current frame counter
        if let lastDate = roll.lastExposureDate {
            let seconds = Int(Date().timeIntervalSince(lastDate))
            let ago: String
            if seconds < 60 {
                ago = "now"
            } else if seconds < 3600 {
                ago = "\(seconds / 60)m ago"
            } else if seconds < 86400 {
                ago = "\(seconds / 3600)h ago"
            } else {
                ago = "\(seconds / 86400)d ago"
            }
            result += " • \(ago)"
        }
        return result
    }
}

// MARK: - Log Exposure Intent

struct LogExposureIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Exposure"
    static var description = IntentDescription("Log a new exposure with current location and timestamp")

    @Parameter(title: "Camera?")
    var camera: CameraEntity

    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Log exposure on \(\.$camera)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let context = SharedModelContainer.shared.mainContext

        // Find the camera and its active roll
        let cameraID = camera.id
        let cameras = try context.fetch(FetchDescriptor<Camera>())
        guard let dbCamera = cameras.first(where: { $0.id == cameraID }),
              let roll = dbCamera.activeRoll else {
            throw $camera.needsValueError("Pick a camera with a loaded roll")
        }

        // Create the log item
        let item = LogItem(roll: roll)

        // Try to get location (geocoding happens on next app launch)
        let location = await getCurrentLocation()
        if let location = location {
            item.setLocation(location)
        }

        context.insert(item)
        roll.logItems = (roll.logItems ?? []) + [item]
        roll.lastExposureDate = item.createdAt

        try context.save()

        let exposureCount = (roll.logItems ?? []).count

        return .result(value: "Logged exposure \(exposureCount) on \(dbCamera.name) with roll \(roll.filmStock)")
    }

    @MainActor
    private func getCurrentLocation() async -> CLLocation? {
        let manager = CLLocationManager()

        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let delegate = OneTimeLocationDelegate { location in
                continuation.resume(returning: location)
            }
            manager.delegate = delegate
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            objc_setAssociatedObject(delegate, "manager", manager, .OBJC_ASSOCIATION_RETAIN)
            manager.requestLocation()

            // Timeout after 10s — the task retains the delegate, keeping it alive
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                delegate.timeout()
            }
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

    /// Called by the timeout task to ensure the continuation is always resumed.
    func timeout() {
        guard !hasCompleted else { return }
        hasCompleted = true
        completion(nil)
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
