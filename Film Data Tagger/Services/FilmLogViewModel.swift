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
    let cameraManager = CameraManager()

    private static let lastLaunchKey = "lastAppLaunchDate"
    private static let referencePhotosKey = "referencePhotosEnabled"

    var referencePhotosEnabled: Bool = UserDefaults.standard.object(forKey: referencePhotosKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(referencePhotosEnabled, forKey: Self.referencePhotosKey) }
    }

    var activeRoll: Roll?

    /// The sorted, non-deleted items for the active roll. All mutations go through the view model.
    private(set) var logItems: [LogItem] = []

    // MARK: - Live location state
    var currentPlaceName: String?
    var currentLocation: CLLocation? { locationManager.currentLocation }
    private var lastGeocodedLocation: CLLocation?
    nonisolated(unsafe) private var geocodeTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    deinit {
        geocodeTask?.cancel()
    }

    // MARK: - Setup

    func setup() {
        locationManager.requestPermission()
        if referencePhotosEnabled {
            Task {
                let granted = await cameraManager.requestPermission()
                if granted {
                    cameraManager.start()
                } else {
                    referencePhotosEnabled = false
                }
            }
        }
        loadOrCreateActiveRoll()
        geocodeRecentUngeocodedItems()
        recordAppLaunch()
        startLiveGeocoding()
    }

    private func recordAppLaunch() {
        UserDefaults.standard.set(Date(), forKey: Self.lastLaunchKey)
    }

    private var lastAppLaunch: Date? {
        UserDefaults.standard.object(forKey: Self.lastLaunchKey) as? Date
    }

    private func reloadItems() {
        logItems = (activeRoll?.logItems ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
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
                reloadItems()
            } else {
                createDefaultRoll()
            }
        } catch {
            print("Failed to fetch rolls: \(error)")
            createDefaultRoll()
        }
    }

    private func createDefaultRoll() {
        let camera = Camera(name: "Olympus XA")
        modelContext.insert(camera)

        let roll = Roll(filmStock: "Kodak Portra 400", camera: camera)
        modelContext.insert(roll)

        activeRoll = roll
        reloadItems()
    }

    // MARK: - Live Geocoding

    private func startLiveGeocoding() {
        geocodeTask = Task {
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

    // MARK: - Logging

    func logExposure() async {
        guard let roll = activeRoll else { return }

        let item = LogItem(roll: roll)
        let location = locationManager.currentLocation

        if let location = location {
            item.setLocation(location)
        }

        // Use the pre-computed place name for instant display
        item.placeName = currentPlaceName

        // Capture reference photo before inserting so the item appears complete
        if referencePhotosEnabled {
            item.photoData = await cameraManager.capturePhoto()
        }

        modelContext.insert(item)
        roll.logItems.append(item)
        roll.touch()
        logItems.append(item)

        // If we don't have a geocode yet, do it in the background
        if item.placeName == nil, let location = location {
            Task {
                item.placeName = await Geocoder.placeName(for: location)
            }
        }
    }

    func logPlaceholder() {
        guard let roll = activeRoll else { return }
        let item = LogItem.placeholder(roll: roll)
        modelContext.insert(item)
        roll.logItems.append(item)
        roll.touch()
        logItems.append(item)
    }

    func deleteItem(_ item: LogItem) {
        item.softDelete()
        logItems.removeAll { $0.id == item.id }
    }

    /// Move a placeholder to just before the target item.
    func movePlaceholder(_ item: LogItem, before target: LogItem) {
        guard item.isPlaceholder, item.id != target.id else { return }
        let others = logItems.filter { $0.id != item.id }
        guard let targetIndex = others.firstIndex(where: { $0.id == target.id }) else { return }

        if targetIndex == 0 {
            item.createdAt = others[0].createdAt.addingTimeInterval(-1)
        } else {
            let a = others[targetIndex - 1].createdAt
            let b = others[targetIndex].createdAt
            item.createdAt = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2.0)
        }

        reloadItems()
    }

    /// Move a placeholder to just after the target item.
    func movePlaceholder(_ item: LogItem, after target: LogItem) {
        guard item.isPlaceholder, item.id != target.id else { return }
        let others = logItems.filter { $0.id != item.id }
        guard let targetIndex = others.firstIndex(where: { $0.id == target.id }) else { return }

        if targetIndex == others.count - 1 {
            item.createdAt = others[targetIndex].createdAt.addingTimeInterval(1)
        } else {
            let a = others[targetIndex].createdAt
            let b = others[targetIndex + 1].createdAt
            item.createdAt = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2.0)
        }

        reloadItems()
    }

    /// Move a placeholder to after the last item.
    func movePlaceholderToEnd(_ item: LogItem) {
        guard item.isPlaceholder else { return }
        let others = logItems.filter { $0.id != item.id }
        let lastDate = others.last?.createdAt ?? Date()
        item.createdAt = lastDate.addingTimeInterval(1)
        reloadItems()
    }

    func toggleReferencePhotos() {
        if !referencePhotosEnabled {
            // Turning on — check permission first
            Task {
                let granted = await cameraManager.requestPermission()
                if granted {
                    referencePhotosEnabled = true
                    cameraManager.start()
                }
                // If denied, iOS won't re-prompt — user must go to Settings.
                // permissionDenied is set on CameraManager for the UI to react to.
            }
        } else {
            referencePhotosEnabled = false
            cameraManager.stop()
        }
    }

    var canLogExposure: Bool {
        activeRoll != nil
    }

    func finishRoll() {
        guard let roll = activeRoll else { return }
        roll.softDelete()
        createDefaultRoll()
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

}
