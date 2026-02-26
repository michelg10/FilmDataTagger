//
//  FilmLogViewModel.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftUI
import SwiftData
import CoreData
import CoreLocation

@Observable
@MainActor
final class FilmLogViewModel {
    private let modelContext: ModelContext
    private let locationManager = LocationManager()
    private let settings = AppSettings.shared
    let cameraManager = CameraManager()

    var referencePhotosEnabled: Bool {
        get { settings.referencePhotosEnabled }
        set { settings.referencePhotosEnabled = newValue }
    }

    /// The currently open (viewed) roll. May or may not be the active roll for its camera.
    var openRoll: Roll? {
        didSet {
            settings.openRollId = openRoll?.id
            if let roll = openRoll {
                openCamera = roll.camera
            }
        }
    }

    /// The sorted items for the open roll/group. All mutations go through the view model.
    private(set) var logItems: [LogItem] = []

    /// The currently selected camera. Derived from openRoll when a roll is set,
    /// or persisted independently when no roll is selected.
    var openCamera: Camera? {
        didSet { settings.openCameraId = openCamera?.id }
    }

    /// Total roll capacity (including extra pre-first-frame exposures).
    var rollCapacity: Int { openRoll?.totalCapacity ?? 36 }

    // MARK: - Instant film state

    var activeInstantFilmGroup: InstantFilmGroup?
    var activeInstantFilmCamera: InstantFilmCamera?
    var isInstantFilmMode: Bool { activeInstantFilmGroup != nil }

    // MARK: - Live location state
    var currentPlaceName: String?
    var currentLocation: CLLocation? { locationManager.currentLocation }
    private var lastGeocodedLocation: CLLocation?
    nonisolated(unsafe) private var geocodeTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated(unsafe) private var remoteChangeObserver: Any?

    deinit {
        geocodeTask?.cancel()
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        observeRemoteChanges()
    }

    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadItems()
            }
        }
    }

    private func recordAppLaunch() {
        settings.lastAppLaunchDate = Date()
    }

    private func reloadItems() {
        if let group = activeInstantFilmGroup {
            // Instant film: aggregate all logItems across all rolls of all sub-cameras
            logItems = (group.cameras ?? [])
                .flatMap { $0.rolls ?? [] }
                .flatMap { $0.logItems ?? [] }
                .sorted { $0.createdAt < $1.createdAt }
        } else {
            logItems = (openRoll?.logItems ?? [] as [LogItem])
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func loadOrCreateActiveRoll() {
        if !settings.isInitialized {
            createDefaultRoll()
            settings.isInitialized = true
            return
        }

        // 1. Try persisted instant film group
        if let storedGroupId = settings.activeInstantFilmGroupId {
            let descriptor = FetchDescriptor<InstantFilmGroup>(
                predicate: #Predicate<InstantFilmGroup> { $0.id == storedGroupId }
            )
            if let group = try? modelContext.fetch(descriptor).first {
                let camera: InstantFilmCamera?
                if let storedCameraId = settings.activeInstantFilmCameraId {
                    camera = (group.cameras ?? []).first { $0.id == storedCameraId }
                } else {
                    camera = nil
                }
                switchToInstantFilmGroup(group, camera: camera)
                return
            }
        }

        // 2. Try the persisted open roll ID
        if let storedId = settings.openRollId {
            let descriptor = FetchDescriptor<Roll>(
                predicate: #Predicate<Roll> { roll in
                    roll.id == storedId
                }
            )
            if let roll = try? modelContext.fetch(descriptor).first {
                openRoll = roll
                reloadItems()
                return
            }
        }

        // 3. Try the persisted open camera ID (no roll selected)
        if let storedCameraId = settings.openCameraId {
            let descriptor = FetchDescriptor<Camera>(
                predicate: #Predicate<Camera> { $0.id == storedCameraId }
            )
            if let camera = try? modelContext.fetch(descriptor).first {
                openCamera = camera
                return
            }
        }

        // 4. Fallback: find any active regular roll
        let activeDescriptor = FetchDescriptor<Roll>(
            predicate: #Predicate<Roll> { $0.isActive == true },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        if let roll = try? modelContext.fetch(activeDescriptor).first {
            openRoll = roll
            reloadItems()
            return
        }
    }

    private func createDefaultRoll() {
        let camera = Camera(name: "Olympus XA", listOrder: nextCameraListOrder())
        modelContext.insert(camera)

        let roll = Roll(filmStock: "Kodak Portra 400", camera: camera)
        modelContext.insert(roll)

        openRoll = roll
        reloadItems()
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

    // MARK: - Logging

    func logExposure() async {
        let roll: Roll
        if isInstantFilmMode {
            guard let subCamera = activeInstantFilmCamera else { return }
            roll = activePackForSubCamera(subCamera)
        } else {
            guard let openRoll else { return }
            activateRollIfNeeded(openRoll)
            roll = openRoll
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
        roll.logItems = (roll.logItems ?? []) + [item]
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
            guard let openRoll else { return }
            roll = openRoll
        }
        let item = LogItem.placeholder(roll: roll)
        modelContext.insert(item)
        roll.logItems = (roll.logItems ?? []) + [item]
        roll.touch()
        logItems.append(item)
    }

    func deleteItem(_ item: LogItem) {
        modelContext.delete(item)
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
        openRoll != nil || (activeInstantFilmGroup != nil && activeInstantFilmCamera != nil)
    }

    // MARK: - Roll Management

    @discardableResult
    func createRoll(camera: Camera, filmStock: String, capacity: Int = 36) -> Roll {
        // Deactivate any currently active roll on this camera
        for roll in camera.rolls ?? [] where roll.isActive {
            roll.isActive = false
        }

        let roll = Roll(filmStock: filmStock, camera: camera, capacity: capacity)
        modelContext.insert(roll)
        camera.rolls = (camera.rolls ?? []) + [roll]

        switchToRoll(roll)
        return roll
    }

    func switchToRoll(_ roll: Roll) {
        // Clear instant film state
        activeInstantFilmGroup = nil
        activeInstantFilmCamera = nil
        settings.activeInstantFilmGroupId = nil
        settings.activeInstantFilmCameraId = nil

        openRoll = roll

        reloadItems()
    }

    func editRoll(_ roll: Roll, filmStock: String, capacity: Int) {
        roll.filmStock = filmStock
        roll.capacity = capacity
        roll.touch()
        reloadItems()
    }

    /// If the roll isn't already the active roll for its camera, activate it
    /// (deactivating the previous active roll on that camera).
    private func activateRollIfNeeded(_ roll: Roll) {
        guard !roll.isActive, let camera = roll.camera else { return }
        for r in camera.rolls ?? [] where r.isActive {
            r.isActive = false
        }
        roll.isActive = true
    }

    func cycleExtraExposures() {
        guard let roll = openRoll else { return }
        let itemCount = (roll.logItems ?? []).count
        let maxExtra = min(4, itemCount)
        let next = roll.extraExposures + 1
        roll.extraExposures = next > maxExtra ? 0 : next
        playHaptic(.cycleExtraExposures)
        reloadItems()
    }

    func deleteRoll(_ roll: Roll) {
        let camera = roll.camera
        modelContext.delete(roll)
        if openRoll?.id == roll.id {
            openRoll = nil
            logItems = []
            openCamera = camera
        }
    }

    // MARK: - Camera Management

    @discardableResult
    func createCamera(name: String) -> Camera {
        let camera = Camera(name: name, listOrder: nextCameraListOrder())
        modelContext.insert(camera)
        return camera
    }

    func renameCamera(_ camera: Camera, to name: String) {
        camera.name = name
    }

    func renameInstantFilmGroup(_ group: InstantFilmGroup, to name: String) {
        group.name = name
    }

    func deleteCamera(_ camera: Camera) {
        if openCamera?.id == camera.id {
            openRoll = nil
            openCamera = nil
            logItems = []
        }
        modelContext.delete(camera)
    }

    /// All cameras and instant film groups for the camera list, sorted by user-defined order.
    func allCameraListEntries() -> [any CameraListEntry] {
        let cameras: [Camera] = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let groups: [InstantFilmGroup] = (try? modelContext.fetch(FetchDescriptor<InstantFilmGroup>())) ?? []

        let entries: [any CameraListEntry] = cameras + groups

        return entries.sorted { a, b in
            if a.listOrder != b.listOrder {
                return a.listOrder < b.listOrder
            }
            if a.createdAt != b.createdAt {
                return a.createdAt < b.createdAt
            }
            return a.id.uuidString < b.id.uuidString
        }
    }

    func reorderCameraListEntries(_ orderedIDs: [UUID]) {
        let cameras: [Camera] = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let groups: [InstantFilmGroup] = (try? modelContext.fetch(FetchDescriptor<InstantFilmGroup>())) ?? []
        let cameraByID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        let groupByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        // Ensure IDs not present in orderedIDs stay in their current relative order.
        let existingEntries: [any CameraListEntry] = cameras + groups
        let existingSortedIDs = existingEntries
            .sorted {
                if $0.listOrder != $1.listOrder {
                    return $0.listOrder < $1.listOrder
                }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map(\.id)
        let movedSet = Set(orderedIDs)
        let finalOrder = orderedIDs + existingSortedIDs.filter { !movedSet.contains($0) }

        for (index, id) in finalOrder.enumerated() {
            if let camera = cameraByID[id] {
                camera.listOrder = Double(index)
            } else if let group = groupByID[id] {
                group.listOrder = Double(index)
            }
        }
    }

    // MARK: - Instant Film Group Management

    @discardableResult
    func createInstantFilmGroup(name: String) -> InstantFilmGroup {
        let group = InstantFilmGroup(name: name, listOrder: nextCameraListOrder())
        modelContext.insert(group)
        return group
    }

    func deleteInstantFilmGroup(_ group: InstantFilmGroup) {
        if activeInstantFilmGroup?.id == group.id {
            activeInstantFilmGroup = nil
            activeInstantFilmCamera = nil
            settings.activeInstantFilmGroupId = nil
            settings.activeInstantFilmCameraId = nil
            logItems = []
        }
        modelContext.delete(group)
    }

    @discardableResult
    func addInstantFilmCamera(to group: InstantFilmGroup, name: String, packCapacity: Int) -> InstantFilmCamera {
        let camera = InstantFilmCamera(name: name, packCapacity: packCapacity, group: group)
        modelContext.insert(camera)
        group.cameras = (group.cameras ?? []) + [camera]

        // Create the first pack (roll) for this camera
        let pack = Roll(filmStock: group.name, capacity: packCapacity)
        pack.instantFilmCamera = camera
        modelContext.insert(pack)
        camera.rolls = (camera.rolls ?? []) + [pack]

        return camera
    }

    func removeInstantFilmCamera(_ camera: InstantFilmCamera) {
        if activeInstantFilmCamera?.id == camera.id {
            // Switch to another sub-camera in the group if available
            let remaining = (activeInstantFilmGroup?.cameras ?? []).filter { $0.id != camera.id }
            activeInstantFilmCamera = remaining.first
            settings.activeInstantFilmCameraId = activeInstantFilmCamera?.id
            reloadItems()
        }
        modelContext.delete(camera)
    }

    func switchToInstantFilmGroup(_ group: InstantFilmGroup, camera: InstantFilmCamera? = nil) {
        // Clear regular camera state
        openRoll = nil

        activeInstantFilmGroup = group
        settings.activeInstantFilmGroupId = group.id
        activeInstantFilmCamera = camera ?? (group.cameras ?? []).first
        settings.activeInstantFilmCameraId = activeInstantFilmCamera?.id
        reloadItems()
    }

    func switchInstantFilmCamera(_ camera: InstantFilmCamera) {
        activeInstantFilmCamera = camera
        settings.activeInstantFilmCameraId = camera.id
    }

    private func nextCameraListOrder() -> Double {
        let cameras: [Camera] = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let groups: [InstantFilmGroup] = (try? modelContext.fetch(FetchDescriptor<InstantFilmGroup>())) ?? []
        let maxOrder = (cameras.map(\.listOrder) + groups.map(\.listOrder)).max() ?? -1
        return maxOrder + 1
    }

    /// Returns the active pack (roll) for a sub-camera, creating a new one if the current pack is full.
    private func activePackForSubCamera(_ camera: InstantFilmCamera) -> Roll {
        let activePacks = (camera.rolls ?? []).filter { $0.isActive }
        if let pack = activePacks.last {
            let frameCount = (pack.logItems ?? []).count
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
        camera.rolls = (camera.rolls ?? []) + [newPack]
        return newPack
    }

    /// Total shots for a sub-camera across all its packs.
    func totalFrameCount(for camera: InstantFilmCamera) -> Int {
        (camera.rolls ?? [])
            .flatMap { $0.logItems ?? [] }
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
            let cutoffDate = min(sevenDaysAgo, settings.lastAppLaunchDate ?? Date.distantPast)

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

}
