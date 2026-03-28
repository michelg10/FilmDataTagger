//
//  FilmLogViewModel.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftUI
import SwiftData
internal import CoreData
import CoreLocation
import os.log

@Observable
@MainActor
final class FilmLogViewModel {
    private let modelContext: ModelContext
    private let settings = AppSettings.shared
    let cameraManager = CameraManager()
    let locationService = LocationService()

    var referencePhotosEnabled: Bool {
        didSet { settings.referencePhotosEnabled = referencePhotosEnabled }
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

    // MARK: - Location (proxied from LocationService)
    var geocodingState: GeocodingState { locationService.geocodingState }
    /// Display-friendly location text that avoids flashing "Locating..." during re-geocoding.
    var displayLocationText: String {
        locationService.displayPlaceName ?? geocodingState.displayText
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.referencePhotosEnabled = AppSettings.shared.referencePhotosEnabled
    }

    nonisolated(unsafe) private var remoteChangeObserver: Any?

    deinit {
        if let observer = remoteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    func setup() {
        switch settings.referencePhotoStartup {
        case .preserveLast: break
        case .on: referencePhotosEnabled = true
        case .off: referencePhotosEnabled = false
        }
        locationService.setup()
        syncAllCameraCaches()
        loadOrCreateActiveRoll()
        scheduleRemoteChangeMaintenance() // deferred: repairDuplicateActiveRolls + geocode backfill
        repairPlaceholderTimestamps()
        let cutoffDate = min(
            Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            settings.lastAppLaunchDate ?? Date.distantPast
        )
        locationService.geocodeRecentItems(container: modelContext.container, since: cutoffDate) { [weak self] results in
            self?.applyGeocodingResults(results)
        }
        recordAppLaunch()
        observeRemoteChanges()
        cleanOrphanedDataIfNeeded()
    }

    /// Geocode items logged since the app was last in the foreground
    /// (e.g. exposures logged via Shortcuts while the app was backgrounded).
    func geocodeUngeocodedItems() {
        let cutoff = settings.lastForegroundDate ?? Date()
        settings.lastForegroundDate = Date()
        reloadItems()
        locationService.geocodeRecentItems(container: modelContext.container, since: cutoff) { [weak self] results in
            self?.applyGeocodingResults(results)
        }
    }

    /// Apply geocoded place names to items on the main context and save.
    private func applyGeocodingResults(_ results: [(UUID, GeocodingResult)]) {
        guard !results.isEmpty else { return }
        for (id, result) in results {
            // Check in-memory logItems first (fast path)
            let item: LogItem?
            if let found = logItems.first(where: { $0.id == id }) {
                item = found
            } else {
                let descriptor = FetchDescriptor<LogItem>(predicate: #Predicate { $0.id == id })
                item = try? modelContext.fetch(descriptor).first
            }
            if let item {
                if let placeName = result.placeName { item.placeName = placeName }
                if let cityName = result.cityName { item.cityName = cityName }
            }
        }
        save()
    }

    private var remoteMaintenanceTask: Task<Void, Never>?

    private func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                debugLog("Remote change notification received")
                // Immediate — UI correctness
                self.validateOpenState()
                self.reloadItems()

                // Debounced — expensive maintenance that doesn't need to run per-notification
                self.scheduleRemoteChangeMaintenance()
            }
        }
    }

    private func scheduleRemoteChangeMaintenance() {
        remoteMaintenanceTask?.cancel()
        remoteMaintenanceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.repairDuplicateActiveRolls()
            self.syncAllCameraCaches()
            self.geocodeUngeocodedVisibleItems()
        }
    }

    /// Geocode any visible items that have a location but no place name (e.g., items logged via Shortcuts).
    private func geocodeUngeocodedVisibleItems() {
        let pending = logItems.compactMap { item -> (UUID, CLLocation)? in
            guard item.placeName == nil, let lat = item.latitude, let lon = item.longitude else { return nil }
            return (item.id, CLLocation(latitude: lat, longitude: lon))
        }
        guard !pending.isEmpty else { return }
        Task { [weak self] in
            let results = await Geocoder.geocodeBatch(pending)
            self?.applyGeocodingResults(results)
        }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FilmDataTagger", category: "data")

    private func save() {
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("SwiftData save failed: \(error)")
            debugLog("SwiftData save failed: \(error)")
        }
    }

    private func recordAppLaunch() {
        settings.lastAppLaunchDate = Date()
        settings.lastForegroundDate = Date()
    }

    private func reloadItems() {
        let items = openRoll?.logItems ?? [] as [LogItem]
        logItems = items.sorted { $0.createdAt < $1.createdAt }
        // Sync cached counts while we have the data faulted
        openRoll?.exposureCount = items.count
        if let camera = openCamera { syncCameraCache(camera) }
    }

    /// Rebuild cached summary fields on all cameras and rolls.
    /// Heavy work (relationship faulting) runs on a background context to keep main thread free.
    /// Only saves if any cached values actually changed, to avoid triggering a feedback loop
    /// with NSPersistentStoreRemoteChange notifications.
    private func syncAllCameraCaches() {
        let container = modelContext.container
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let cameras = (try? context.fetch(FetchDescriptor<Camera>())) ?? []
            var didChange = false
            for camera in cameras {
                let rolls = camera.rolls ?? []
                // Sync roll exposure counts first — camera cache depends on them
                for roll in rolls {
                    let actual = (roll.logItems ?? []).count
                    if roll.exposureCount != actual {
                        roll.exposureCount = actual
                        didChange = true
                    }
                }
                let active = rolls.first(where: \.isActive)
                let newRollCount = rolls.count
                let newTotalExposureCount = rolls.reduce(0) { $0 + $1.exposureCount }
                let newLastUsedDate = rolls.compactMap { $0.lastExposureDate ?? ($0.exposureCount > 0 ? $0.createdAt : nil) }.max()
                let newActiveFilmStock = active?.filmStock
                let newActiveExposureCount = active?.exposureCount
                let newActiveCapacity = active?.totalCapacity

                if camera.cachedRollCount != newRollCount ||
                   camera.cachedTotalExposureCount != newTotalExposureCount ||
                   camera.cachedLastUsedDate != newLastUsedDate ||
                   camera.cachedActiveFilmStock != newActiveFilmStock ||
                   camera.cachedActiveExposureCount != newActiveExposureCount ||
                   camera.cachedActiveCapacity != newActiveCapacity {
                    camera.cachedRollCount = newRollCount
                    camera.cachedTotalExposureCount = newTotalExposureCount
                    camera.cachedLastUsedDate = newLastUsedDate
                    camera.cachedActiveFilmStock = newActiveFilmStock
                    camera.cachedActiveExposureCount = newActiveExposureCount
                    camera.cachedActiveCapacity = newActiveCapacity
                    didChange = true
                }
            }
            if didChange { try? context.save() }
        }
    }

    /// Sync cached summary fields on a Camera from its rolls.
    /// Call after any mutation that changes roll count, exposure count, or active roll.
    private func syncCameraCache(_ camera: Camera) {
        let rolls = camera.rolls ?? []
        let active = rolls.first(where: \.isActive)
        camera.cachedRollCount = rolls.count
        camera.cachedTotalExposureCount = rolls.reduce(0) { $0 + $1.exposureCount }
        camera.cachedLastUsedDate = rolls.compactMap { $0.lastExposureDate ?? ($0.exposureCount > 0 ? $0.createdAt : nil) }.max()
        camera.cachedActiveFilmStock = active?.filmStock
        camera.cachedActiveExposureCount = active?.exposureCount
        camera.cachedActiveCapacity = active?.totalCapacity
    }

    /// Verify that all in-memory references to persisted objects are still valid.
    /// Clears stale references caused by remote (iCloud) changes.
    private func validateOpenState() {
        if let roll = openRoll {
            let rollId = roll.id
            let descriptor = FetchDescriptor<Roll>(predicate: #Predicate { $0.id == rollId })
            let freshRoll = try? modelContext.fetch(descriptor).first
            if freshRoll == nil {
                debugLog("validateOpenState: roll fetch returned nil for \(rollId)")
                // Roll was deleted remotely
                openRoll = nil
                logItems = []
            } else if freshRoll?.camera == nil {
                // A roll's camera is constant — if the camera is gone, the roll is about to be
                // cascade-deleted too, we just haven't received that sync yet. Clear state now.
                openRoll = nil
                openCamera = nil
                logItems = []
            } else if !roll.isActive {
                // Roll was deactivated on another device (e.g., finished)
                // Stay on the roll so the user can see it, but clear won't surprise them
            }
        }
        if let cameraId = openCamera?.id {
            let descriptor = FetchDescriptor<Camera>(predicate: #Predicate { $0.id == cameraId })
            if (try? modelContext.fetch(descriptor).first) == nil {
                debugLog("validateOpenState: camera fetch returned nil for \(cameraId)")
                openCamera = nil
            }
        }
    }

    /// Ensure each camera has at most one active roll.
    /// Keeps the most recently used one, deactivates the rest.
    private func repairDuplicateActiveRolls() {
        let cameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        var didRepair = false
        for camera in cameras {
            let activeRolls = (camera.rolls ?? []).filter(\.isActive)
            guard activeRolls.count > 1 else { continue }
            debugLog("repairDuplicateActiveRolls: camera \(camera.name) has \(activeRolls.count) active rolls")
            // Keep the one with the most recent exposure, or most recently created
            let keeper = activeRolls
                .sorted { ($0.lastExposureDate ?? .distantPast) > ($1.lastExposureDate ?? .distantPast) }
                .first!
            for roll in activeRolls where roll.id != keeper.id {
                roll.isActive = false
            }
            didRepair = true
        }
        if didRepair { save() }
    }

    /// Re-interpolate placeholder timestamps between real exposures.
    /// Repairs precision exhaustion from repeated drag reordering.
    private func repairPlaceholderTimestamps() {
        guard let roll = openRoll else { return }
        let items = (roll.logItems ?? []).sorted { $0.createdAt < $1.createdAt }
        // Need at least 2 items and at least one real timestamp to anchor against
        guard items.count >= 2, items.contains(where: \.hasRealCreatedAt) else { return }

        var didRepair = false
        var i = 0
        while i < items.count {
            // Find runs of consecutive placeholders
            guard !items[i].hasRealCreatedAt else { i += 1; continue }
            let runStart = i
            while i < items.count && !items[i].hasRealCreatedAt { i += 1 }
            let runEnd = i // exclusive

            // Boundaries: real timestamp before and after the run
            let before = runStart > 0 ? items[runStart - 1].createdAt : items[runEnd < items.count ? runEnd : runStart].createdAt.addingTimeInterval(-Double(runEnd - runStart + 1))
            let after = runEnd < items.count ? items[runEnd].createdAt : before.addingTimeInterval(Double(runEnd - runStart + 1))

            let count = runEnd - runStart
            for j in 0..<count {
                let fraction = Double(j + 1) / Double(count + 1)
                let newTime = before.addingTimeInterval(after.timeIntervalSince(before) * fraction)
                if items[runStart + j].createdAt != newTime {
                    items[runStart + j].createdAt = newTime
                    didRepair = true
                }
            }
        }
        if didRepair { save() }
    }

    /// Delete orphaned rolls (no camera) and orphaned exposures (no roll).
    /// Uses a two-strike approach: orphans detected on one run are only deleted if they're still
    /// orphaned on the next run (72h+ later). This prevents deleting valid CloudKit data that
    /// arrived out of order (children before parents).
    private func cleanOrphanedDataIfNeeded() {
        if let lastClean = settings.lastDataCleanDate,
           Date().timeIntervalSince(lastClean) < 72 * 60 * 60 { return }

        let defaults = UserDefaults.standard
        let previousRollIDs = Set(defaults.stringArray(forKey: AppSettingsKeys.pendingOrphanRollIDs) ?? [])
        let previousItemIDs = Set(defaults.stringArray(forKey: AppSettingsKeys.pendingOrphanItemIDs) ?? [])

        let container = modelContext.container
        Task.detached(priority: .utility) {
            let context = ModelContext(container)

            // Find current orphan candidates on the background context
            let orphanedRollDescriptor = FetchDescriptor<Roll>(
                predicate: #Predicate<Roll> {
                    $0.camera == nil
                }
            )
            let orphanedRolls = (try? context.fetch(orphanedRollDescriptor)) ?? []
            let candidateRollIDs = orphanedRolls.map { $0.id.uuidString }

            let orphanedItemDescriptor = FetchDescriptor<LogItem>(
                predicate: #Predicate<LogItem> { $0.roll == nil }
            )
            let candidateItemIDs = ((try? context.fetch(orphanedItemDescriptor)) ?? []).map { $0.id.uuidString }

            // Two-strike: only delete IDs that were also flagged on the previous run
            let confirmedRollIDs = Set(candidateRollIDs).intersection(previousRollIDs)
            let confirmedItemIDs = Set(candidateItemIDs).intersection(previousItemIDs)

            await MainActor.run { [candidateRollIDs, candidateItemIDs, confirmedRollIDs, confirmedItemIDs] in
                // Persist current candidates for the next run's comparison
                defaults.set(candidateRollIDs, forKey: AppSettingsKeys.pendingOrphanRollIDs)
                defaults.set(candidateItemIDs, forKey: AppSettingsKeys.pendingOrphanItemIDs)

                // Delete only confirmed (two-strike) orphans, re-checking on main context
                var deletedRolls = 0
                for idString in confirmedRollIDs {
                    guard let id = UUID(uuidString: idString) else { continue }
                    let descriptor = FetchDescriptor<Roll>(predicate: #Predicate { $0.id == id })
                    if let roll = try? self.modelContext.fetch(descriptor).first,
                       roll.camera == nil {
                        self.modelContext.delete(roll)
                        deletedRolls += 1
                    }
                }
                var deletedItems = 0
                for idString in confirmedItemIDs {
                    guard let id = UUID(uuidString: idString) else { continue }
                    let descriptor = FetchDescriptor<LogItem>(predicate: #Predicate { $0.id == id })
                    if let item = try? self.modelContext.fetch(descriptor).first,
                       item.roll == nil {
                        self.modelContext.delete(item)
                        deletedItems += 1
                    }
                }
                if deletedRolls > 0 || deletedItems > 0 {
                    Self.logger.info("Data clean: \(deletedRolls) orphaned roll(s), \(deletedItems) orphaned exposure(s)")
                    self.save()
                }
                AppSettings.shared.lastDataCleanDate = Date()
            }
        }
    }

    private func loadOrCreateActiveRoll() {
        // 1. Try the persisted open roll ID
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

        // 2. Try the persisted open camera ID (no roll selected)
        if let storedCameraId = settings.openCameraId {
            let descriptor = FetchDescriptor<Camera>(
                predicate: #Predicate<Camera> { $0.id == storedCameraId }
            )
            if let camera = try? modelContext.fetch(descriptor).first {
                openCamera = camera
                return
            }
        }

        // 3. No persisted state matched — drop user at the root CameraListView.
    }

    // MARK: - Logging

    private var pendingCaptures = 0
    private var isCapturing = false

    func logExposure() async {
        pendingCaptures += 1
        guard !isCapturing else { return }
        isCapturing = true

        // Snapshot state before the await — roll/camera could change during capture
        let targetRoll = openRoll

        // Collect data once — shared across all pending taps
        let location = settings.locationEnabled ? locationService.currentLocation : nil
        let placeName = locationService.geocodingState.persistablePlaceName
        let cityName = locationService.geocodingState.persistableCityName
        // If the camera isn't ready yet, capturePhoto returns nil — that's fine,
        // the exposure still logs timestamp + location. Speed of capture matters more than blocking for a photo.
        let maxDimension = settings.photoQuality.maxDimension
        let compressionQuality = settings.photoQuality.compressionQuality
        let rawPhotoData: Data? = if referencePhotosEnabled {
            await cameraManager.capturePhoto()
        } else {
            nil
        }

        // Resize + generate thumbnail off-main so the main thread stays responsive.
        // We await the result so the row appears with its image — no flicker.
        let (photoData, thumbnailData): (Data?, Data?) = if let rawPhotoData {
            await Task.detached(priority: .userInitiated) {
                let resized: Data? = if let maxDimension {
                    CameraManager.resized(rawPhotoData, maxDimension: maxDimension, quality: compressionQuality)
                } else {
                    rawPhotoData
                }
                let thumb = resized.flatMap { CameraManager.generateThumbnail(from: $0) }
                return (resized, thumb)
            }.value
        } else {
            (nil, nil)
        }

        // Drain the counter — any taps during the await are included
        let count = pendingCaptures
        pendingCaptures = 0
        isCapturing = false

        for _ in 0..<count {
            guard let targetRoll else { continue }
            activateRollIfNeeded(targetRoll)
            let roll = targetRoll

            let item = LogItem(roll: roll)
            item.exposureSource = .app
            item.photoData = photoData
            item.thumbnailData = thumbnailData

            if let location {
                item.setLocation(location)
                item.placeName = placeName
                item.cityName = cityName
                AppSettings.shared.cacheShortcutLocation(location)
            }

            // Pre-cache so the row displays without decoding
            if let thumbnailData {
                await ImageCache.shared.preload(for: item.id, data: thumbnailData)
            }

            // SwiftData maintains the inverse: inserting an item with item.roll = roll
            // automatically appends it to roll.logItems. No manual array overwrite needed.
            modelContext.insert(item)
            roll.lastExposureDate = item.createdAt
            roll.exposureCount += 1
            logItems.append(item)

            // If we don't have a geocode yet, do it in the background
            if item.placeName == nil, let location {
                let itemID = item.id
                Task { [weak self] in
                    let result = await Geocoder.geocode(location)
                    self?.applyGeocodingResults([(itemID, result)])
                }
            }
        }
        if let camera = openCamera { syncCameraCache(camera) }
        save()
    }

    // MARK: - Export

    func exportJSON() async -> URL? {
        let container = modelContext.container
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            do {
                return try ExportService.exportJSON(context: context)
            } catch {
                debugLog("exportJSON failed: \(error)")
                return nil
            }
        }.value
    }

    func exportCSV() async -> URL? {
        let container = modelContext.container
        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            do {
                return try ExportService.exportCSV(context: context)
            } catch {
                debugLog("exportCSV failed: \(error)")
                return nil
            }
        }.value
    }

    func logPlaceholder() {
        guard let roll = openRoll else { return }
        let item = LogItem.placeholder(roll: roll)
        modelContext.insert(item)
        roll.exposureCount += 1
        logItems.append(item)
        if let camera = roll.camera { syncCameraCache(camera) }
        save()
    }

    func deleteItem(_ item: LogItem) {
        let roll = item.roll
        let deletedID = item.id
        modelContext.delete(item)
        logItems.removeAll { $0.id == deletedID }
        if let roll {
            roll.exposureCount = max(0, roll.exposureCount - 1)
            recomputeLastExposureDate(for: roll, excluding: deletedID)
            if let camera = roll.camera { syncCameraCache(camera) }
        }
        save()
    }

    /// Move an exposure to a different roll, removing it from the current view.
    func moveItem(_ item: LogItem, to targetRoll: Roll) {
        guard item.roll?.id != targetRoll.id else { return }
        let oldRoll = item.roll

        // Reassigning the to-one side automatically removes from old roll and adds to new.
        item.roll = targetRoll

        if let oldRoll {
            oldRoll.exposureCount = max(0, oldRoll.exposureCount - 1)
            recomputeLastExposureDate(for: oldRoll, excluding: item.id)
        }
        targetRoll.exposureCount += 1
        if let date = item.hasRealCreatedAt ? item.createdAt : nil {
            if targetRoll.lastExposureDate == nil || date > targetRoll.lastExposureDate! {
                targetRoll.lastExposureDate = date
            }
        }

        if let camera = oldRoll?.camera { syncCameraCache(camera) }
        if let camera = targetRoll.camera, camera.id != oldRoll?.camera?.id { syncCameraCache(camera) }

        // Switch to the target roll
        save()
        switchToRoll(targetRoll)
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
        save()
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
        save()
    }

    /// Move a placeholder to after the last item.
    func movePlaceholderToEnd(_ item: LogItem) {
        guard item.isPlaceholder else { return }
        let others = logItems.filter { $0.id != item.id }
        let lastDate = others.last?.createdAt ?? Date()
        item.createdAt = lastDate.addingTimeInterval(1)
        reloadItems()
        save()
    }

    /// Start the camera session if reference photos are enabled. Call on exposure screen appear.
    func ensureCameraRunning() {
        guard referencePhotosEnabled else { return }
        Task {
            let granted = await cameraManager.requestPermission()
            if granted {
                cameraManager.start()
            } else {
                referencePhotosEnabled = false
            }
        }
    }

    /// Schedule camera stop after a delay. Call on exposure screen disappear.
    func scheduleCameraStop() {
        cameraManager.scheduleStop()
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

    // MARK: - Roll Management

    @discardableResult
    func createRoll(camera: Camera, filmStock: String, capacity: Int = 36) -> Roll {
        // Deactivate any currently active roll on this camera
        for roll in camera.rolls ?? [] where roll.isActive {
            roll.isActive = false
        }

        let roll = Roll(filmStock: filmStock, camera: camera, capacity: capacity)
        modelContext.insert(roll)

        syncCameraCache(camera)
        switchToRoll(roll)
        save()
        return roll
    }

    func switchToRoll(_ roll: Roll) {
        openRoll = roll

        reloadItems()
        geocodeUngeocodedVisibleItems()
    }

    func editRoll(_ roll: Roll, filmStock: String, capacity: Int) {
        roll.filmStock = filmStock
        roll.capacity = capacity
        if let camera = roll.camera { syncCameraCache(camera) }
        reloadItems()
        save()
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

    private func recomputeLastExposureDate(for roll: Roll, excluding excludedID: UUID? = nil) {
        roll.lastExposureDate = (roll.logItems ?? [])
            .filter { $0.hasRealCreatedAt && $0.id != excludedID }
            .map(\.createdAt)
            .max()
    }

    func cycleExtraExposures() {
        guard let roll = openRoll else { return }
        let maxExtra = min(4, roll.exposureCount)
        let next = roll.extraExposures + 1
        roll.extraExposures = next > maxExtra ? 0 : next
        playHaptic(.cycleExtraExposures)
        if let camera = roll.camera { syncCameraCache(camera) }
        reloadItems()
        save()
    }

    func deleteRoll(_ roll: Roll) {
        let camera = roll.camera
        modelContext.delete(roll)
        if openRoll?.id == roll.id {
            openRoll = nil
            logItems = []
            openCamera = camera
        }
        if let camera { syncCameraCache(camera) }
        save()
    }

    // MARK: - Camera Management

    @discardableResult
    func createCamera(name: String) -> Camera {
        let camera = Camera(name: name, listOrder: nextCameraListOrder())
        modelContext.insert(camera)
        save()
        return camera
    }

    func renameCamera(_ camera: Camera, to name: String) {
        camera.name = name
        save()
    }

    func deleteCamera(_ camera: Camera) {
        if openCamera?.id == camera.id {
            openRoll = nil
            openCamera = nil
            logItems = []
        }
        modelContext.delete(camera)
        save()
    }

    func reorderCameraListEntries(_ orderedIDs: [UUID]) {
        let cameras: [Camera] = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let cameraByID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })

        // Ensure IDs not present in orderedIDs stay in their current relative order.
        let existingSortedIDs = cameras
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
            cameraByID[id]?.listOrder = Double(index)
        }
        save()
    }

    private func nextCameraListOrder() -> Double {
        let cameras: [Camera] = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        return (cameras.map(\.listOrder).max() ?? -1) + 1
    }
}
