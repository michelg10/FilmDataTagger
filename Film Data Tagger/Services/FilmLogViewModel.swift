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
    private static let activeRollIdKey = "activeRollId"
    private static let activeInstantFilmGroupIdKey = "activeInstantFilmGroupId"
    private static let activeInstantFilmCameraIdKey = "activeInstantFilmCameraId"

    var referencePhotosEnabled: Bool = UserDefaults.standard.object(forKey: referencePhotosKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(referencePhotosEnabled, forKey: Self.referencePhotosKey) }
    }

    var activeRoll: Roll? {
        didSet { activeRollId = activeRoll?.id }
    }

    /// The sorted, non-deleted items for the active roll. All mutations go through the view model.
    private(set) var logItems: [LogItem] = []

    /// The camera for the current active roll.
    var activeCamera: Camera? { activeRoll?.camera }

    /// Roll capacity from the active roll.
    var rollCapacity: Int { activeRoll?.capacity ?? 36 }

    private var activeRollId: UUID? {
        get {
            guard let str = UserDefaults.standard.string(forKey: Self.activeRollIdKey) else { return nil }
            return UUID(uuidString: str)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.activeRollIdKey)
        }
    }

    // MARK: - Instant film state

    var activeInstantFilmGroup: InstantFilmGroup?
    var activeInstantFilmCamera: InstantFilmCamera?
    var isInstantFilmMode: Bool { activeInstantFilmGroup != nil }

    private var activeInstantFilmGroupId: UUID? {
        get {
            guard let str = UserDefaults.standard.string(forKey: Self.activeInstantFilmGroupIdKey) else { return nil }
            return UUID(uuidString: str)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.activeInstantFilmGroupIdKey)
        }
    }

    private var activeInstantFilmCameraId: UUID? {
        get {
            guard let str = UserDefaults.standard.string(forKey: Self.activeInstantFilmCameraIdKey) else { return nil }
            return UUID(uuidString: str)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Self.activeInstantFilmCameraIdKey)
        }
    }

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
        if let group = activeInstantFilmGroup {
            // Instant film: aggregate all logItems across all rolls of all sub-cameras
            logItems = group.cameras
                .filter { $0.deletedAt == nil }
                .flatMap { $0.rolls }
                .filter { $0.deletedAt == nil }
                .flatMap { $0.logItems }
                .filter { $0.deletedAt == nil }
                .sorted { $0.createdAt < $1.createdAt }
        } else {
            logItems = (activeRoll?.logItems ?? [])
                .filter { $0.deletedAt == nil }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func loadOrCreateActiveRoll() {
        // 1. Try persisted instant film group
        if let storedGroupId = activeInstantFilmGroupId {
            let descriptor = FetchDescriptor<InstantFilmGroup>(
                predicate: #Predicate<InstantFilmGroup> { $0.id == storedGroupId && $0.deletedAt == nil }
            )
            if let group = try? modelContext.fetch(descriptor).first {
                let camera: InstantFilmCamera?
                if let storedCameraId = activeInstantFilmCameraId {
                    camera = group.cameras.first { $0.id == storedCameraId && $0.deletedAt == nil }
                } else {
                    camera = nil
                }
                switchToInstantFilmGroup(group, camera: camera)
                return
            }
        }

        // 2. Try the persisted active roll ID
        if let storedId = activeRollId {
            let descriptor = FetchDescriptor<Roll>(
                predicate: #Predicate<Roll> { roll in
                    roll.id == storedId && roll.deletedAt == nil
                }
            )
            if let roll = try? modelContext.fetch(descriptor).first {
                activeRoll = roll
                reloadItems()
                return
            }
        }

        // 3. Fallback: find any active, non-deleted regular roll
        let activeDescriptor = FetchDescriptor<Roll>(
            predicate: #Predicate<Roll> { $0.isActive == true && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        if let roll = try? modelContext.fetch(activeDescriptor).first {
            activeRoll = roll
            reloadItems()
            return
        }

        // 4. Nothing found — create default
        createDefaultRoll()
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
        let roll: Roll
        if isInstantFilmMode {
            guard let subCamera = activeInstantFilmCamera else { return }
            roll = activePackForSubCamera(subCamera)
        } else {
            guard let activeRoll else { return }
            roll = activeRoll
        }

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
        let roll: Roll
        if isInstantFilmMode {
            guard let subCamera = activeInstantFilmCamera else { return }
            roll = activePackForSubCamera(subCamera)
        } else {
            guard let activeRoll else { return }
            roll = activeRoll
        }
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
        activeRoll != nil || (activeInstantFilmGroup != nil && activeInstantFilmCamera != nil)
    }

    // MARK: - Roll Management

    func finishRoll() {
        guard let roll = activeRoll else { return }
        roll.isActive = false
        roll.touch()

        // Temporary: auto-create a new roll on the same camera until we have UI
        if let camera = roll.camera {
            let newRoll = Roll(filmStock: roll.filmStock, camera: camera, capacity: roll.capacity)
            modelContext.insert(newRoll)
            camera.rolls.append(newRoll)
            activeRoll = newRoll
            reloadItems()
        } else {
            activeRoll = nil
            logItems = []
        }
    }

    @discardableResult
    func createRoll(camera: Camera, filmStock: String, capacity: Int = 36) -> Roll {
        // Deactivate any currently active roll on this camera
        for roll in camera.rolls where roll.isActive && roll.deletedAt == nil {
            roll.isActive = false
        }

        let roll = Roll(filmStock: filmStock, camera: camera, capacity: capacity)
        modelContext.insert(roll)
        camera.rolls.append(roll)

        switchToRoll(roll)
        return roll
    }

    func switchToRoll(_ roll: Roll) {
        // Clear instant film state
        activeInstantFilmGroup = nil
        activeInstantFilmCamera = nil
        activeInstantFilmGroupId = nil
        activeInstantFilmCameraId = nil

        activeRoll = roll
        reloadItems()
    }

    func deleteRoll(_ roll: Roll) {
        roll.softDelete()
        if activeRoll?.id == roll.id {
            activeRoll = nil
            logItems = []
        }
    }

    // MARK: - Camera Management

    @discardableResult
    func createCamera(name: String) -> Camera {
        let camera = Camera(name: name)
        modelContext.insert(camera)
        return camera
    }

    func deleteCamera(_ camera: Camera) {
        camera.softDelete()
        // Also soft-delete all rolls on this camera
        for roll in camera.rolls where roll.deletedAt == nil {
            roll.softDelete()
        }
        // If the active roll belonged to this camera, clear state
        if let activeRoll, activeRoll.camera?.id == camera.id {
            self.activeRoll = nil
            logItems = []
        }
    }

    // MARK: - Instant Film Group Management

    @discardableResult
    func createInstantFilmGroup(name: String) -> InstantFilmGroup {
        let group = InstantFilmGroup(name: name)
        modelContext.insert(group)
        return group
    }

    func deleteInstantFilmGroup(_ group: InstantFilmGroup) {
        group.softDelete()
        if activeInstantFilmGroup?.id == group.id {
            activeInstantFilmGroup = nil
            activeInstantFilmCamera = nil
            activeInstantFilmGroupId = nil
            activeInstantFilmCameraId = nil
            logItems = []
        }
    }

    @discardableResult
    func addInstantFilmCamera(to group: InstantFilmGroup, name: String, packCapacity: Int) -> InstantFilmCamera {
        let camera = InstantFilmCamera(name: name, packCapacity: packCapacity, group: group)
        modelContext.insert(camera)
        group.cameras.append(camera)

        // Create the first pack (roll) for this camera
        let pack = Roll(filmStock: group.name, capacity: packCapacity)
        pack.instantFilmCamera = camera
        modelContext.insert(pack)
        camera.rolls.append(pack)

        return camera
    }

    func removeInstantFilmCamera(_ camera: InstantFilmCamera) {
        camera.softDelete()
        for roll in camera.rolls where roll.deletedAt == nil {
            roll.softDelete()
        }
        if activeInstantFilmCamera?.id == camera.id {
            // Switch to another sub-camera in the group if available
            let remaining = activeInstantFilmGroup?.cameras.filter { $0.deletedAt == nil && $0.id != camera.id }
            activeInstantFilmCamera = remaining?.first
            activeInstantFilmCameraId = activeInstantFilmCamera?.id
            reloadItems()
        }
    }

    func switchToInstantFilmGroup(_ group: InstantFilmGroup, camera: InstantFilmCamera? = nil) {
        // Clear regular camera state
        activeRoll = nil

        activeInstantFilmGroup = group
        activeInstantFilmGroupId = group.id
        activeInstantFilmCamera = camera ?? group.cameras.first(where: { $0.deletedAt == nil })
        activeInstantFilmCameraId = activeInstantFilmCamera?.id
        reloadItems()
    }

    func switchInstantFilmCamera(_ camera: InstantFilmCamera) {
        activeInstantFilmCamera = camera
        activeInstantFilmCameraId = camera.id
    }

    /// Returns the active pack (roll) for a sub-camera, creating a new one if the current pack is full.
    private func activePackForSubCamera(_ camera: InstantFilmCamera) -> Roll {
        let activePacks = camera.rolls.filter { $0.deletedAt == nil && $0.isActive }
        if let pack = activePacks.last {
            let frameCount = pack.logItems.filter { $0.deletedAt == nil }.count
            if frameCount < camera.packCapacity {
                return pack
            }
            // Pack is full — deactivate and create new
            pack.isActive = false
            pack.touch()
        }

        let newPack = Roll(filmStock: activeInstantFilmGroup?.name ?? "", capacity: camera.packCapacity)
        newPack.instantFilmCamera = camera
        modelContext.insert(newPack)
        camera.rolls.append(newPack)
        return newPack
    }

    /// Total shots for a sub-camera across all its packs.
    func totalFrameCount(for camera: InstantFilmCamera) -> Int {
        camera.rolls
            .filter { $0.deletedAt == nil }
            .flatMap { $0.logItems }
            .filter { $0.deletedAt == nil }
            .count
    }

    /// Current frame number within the active pack (1-indexed, wraps at pack capacity).
    func packFrameDisplay(for camera: InstantFilmCamera) -> Int {
        let total = totalFrameCount(for: camera)
        guard camera.packCapacity > 0 else { return total }
        return (total % camera.packCapacity)
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
