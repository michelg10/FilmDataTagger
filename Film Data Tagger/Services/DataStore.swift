//
//  DataStore.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/27/26.
//

import Foundation
import SwiftData
import CoreLocation
import Combine
import CoreData

// MARK: - DataStore
actor DataStore: ModelActor {
    let modelExecutor: any ModelExecutor
    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        #if DEBUG
        assert(!Thread.isMainThread, "DataStore must be initialized off the main thread")
        #endif
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
    }

    // MARK: - Publishers

    /// Single signal for remote changes. The VM re-reads `loadAll()` when this fires.
    nonisolated(unsafe) let remoteDataChanged = PassthroughSubject<Void, Never>()

    // MARK: - Startup / Read API

    /// Load ALL metadata into memory as a ready-made tree.
    /// Called once on startup and on remote changes.
    /// Ownership is transferred to the caller — the actor holds no references afterward.
    func loadAll() -> sending [CameraState] {
        #if DEBUG
        assertHighPriority()
        #endif
        var cameras: [Camera] = []
        var allRolls: [Roll] = []
        var allItems: [LogItem] = []
        do {
            cameras = try modelContext.fetch(FetchDescriptor<Camera>(sortBy: [SortDescriptor(\.listOrder)]))
            allRolls = try modelContext.fetch(FetchDescriptor<Roll>())
            allItems = try modelContext.fetch(FetchDescriptor<LogItem>(sortBy: [SortDescriptor(\.createdAt)]))
        } catch {
            debugLog("loadAll fetch failed: \(error)")
        }

        // Build snapshots and seed the diff cache
        let cameraSnapshots = cameras.map { $0.snapshot }
        let rollSnapshots = allRolls.map { $0.snapshot }
        let itemSnapshots = allItems.map { $0.snapshot }
        lastCameras = cameraSnapshots
        lastRolls = rollSnapshots
        lastItems = itemSnapshots

        // Group items by roll ID
        let itemsByRoll = Dictionary(grouping: itemSnapshots, by: { $0.rollID })

        // Group rolls by camera ID
        let rollsByCamera = Dictionary(grouping: rollSnapshots, by: { $0.cameraID })

        // Build the tree
        return cameras.map { camera in
            let cameraRolls = (rollsByCamera[camera.id] ?? [])
                .sorted { ($0.lastExposureDate ?? $0.createdAt) > ($1.lastExposureDate ?? $1.createdAt) }
            let rollStates = cameraRolls.map { roll in
                RollState(snapshot: roll, items: itemsByRoll[roll.id] ?? [])
            }
            return CameraState(snapshot: camera.snapshot, rolls: rollStates)
        }
    }

    /// Warm thumbnails for a specific roll into ImageCache.
    /// Call when navigating to a camera (for its active roll) or switching to a roll.
    func warmRollThumbnails(_ rollID: UUID) async {
        await ImageCache.shared.bookkeeper.recordAccess(rollID)
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        for item in items {
            if let data = item.thumbnailData {
                await ImageCache.shared.preload(for: item.id, data: data)
            }
        }
    }

    /// Provide relationship metadata to the ImageCache bookkeeper so it can decide
    /// which rolls to warm, then fetch item IDs only for those rolls.
    func warmThumbnailCache() async {
        let allCameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let cameraInfo: [(cameraID: UUID, activeRollID: UUID?, rollIDs: [UUID])] = allCameras.map { camera in
            let rolls = camera.rolls ?? []
            let activeRollID = rolls.first(where: \.isActive)?.id
            return (camera.id, activeRollID, rolls.map(\.id))
        }

        let bookkeeper = ImageCache.shared.bookkeeper
        await bookkeeper.load()
        let rollsToWarm = await bookkeeper.rollsToWarm(cameraInfo: cameraInfo)

        var priorityIDs = Set<UUID>()
        for rollID in rollsToWarm {
            let ids = fetchLogItemIDs(forRoll: rollID)
            priorityIDs.formUnion(ids)
        }

        await ImageCache.shared.warmOnLaunch(priorityIDs: priorityIDs)
    }

    // MARK: - Write API

    /// Persist a new exposure. The VM has already updated its local state optimistically.
    /// If the roll is not currently active, it will be activated (and the previous active roll
    /// on the same camera deactivated). This handles the case where the user navigates to
    /// an old roll and starts logging.
    ///
    /// Not high priority: do not await
    func logExposure(
        id: UUID,
        rollID: UUID,
        createdAt: Date,
        source: ExposureSource = .app,
        photoData: Data?,
        thumbnailData: Data?,
        location: CLLocation?,
        placeName: String?,
        cityName: String?
    ) async {
        guard let roll = fetchRoll(rollID) else {
            debugLog("logExposure: roll \(rollID) not found")
            remoteDataChanged.send()
            return
        }
        let item = LogItem(roll: roll)
        item.id = id
        item.createdAt = createdAt
        item.exposureSource = source
        item.photoData = photoData
        item.thumbnailData = thumbnailData
        if let location {
            item.setLocation(location)
            item.placeName = placeName
            item.cityName = cityName
        }
        modelContext.insert(item)

        // Activate the roll if it isn't already (deactivate the previous active roll)
        if !roll.isActive, let camera = roll.camera {
            for r in camera.rolls ?? [] where r.isActive {
                r.isActive = false
            }
            roll.isActive = true
        }

        roll.cachedLastExposureDate = createdAt
        roll.cachedExposureCount += 1
        // Incremental camera cache update — avoids faulting all rolls
        if let camera = roll.camera {
            camera.cachedTotalExposureCount += 1
            if camera.cachedLastUsedDate == nil || createdAt > camera.cachedLastUsedDate! {
                camera.cachedLastUsedDate = createdAt
            }
            // Always update active fields — the roll is guaranteed active at this point
            camera.cachedActiveRollID = roll.id
            camera.cachedActiveFilmStock = roll.filmStock
            camera.cachedActiveExposureCount = roll.cachedExposureCount
            camera.cachedActiveCapacity = roll.totalCapacity
        }
        save()
        if let thumbnailData {
            await ImageCache.shared.preload(for: id, data: thumbnailData)
        }
    }

    /// Persist a new placeholder. The VM has already updated its local state optimistically.
    ///
    /// Not high priority: do not await
    func logPlaceholder(id: UUID, rollID: UUID, createdAt: Date) {
        guard let roll = fetchRoll(rollID) else {
            debugLog("logPlaceholder: roll \(rollID) not found")
            remoteDataChanged.send()
            return
        }
        let item = LogItem.placeholder(roll: roll)
        item.id = id
        item.createdAt = createdAt
        modelContext.insert(item)
        roll.cachedExposureCount += 1
        // Incremental camera cache update — avoids faulting all rolls
        if let camera = roll.camera {
            camera.cachedTotalExposureCount += 1
            if roll.isActive {
                camera.cachedActiveExposureCount = roll.cachedExposureCount
            }
        }
        save()
    }

    /// Delete an item. The VM has already removed it from its local state optimistically.
    /// If the item doesn't exist (e.g., already deleted via CloudKit), re-publish
    /// the current roll items so the VM can reconcile.
    ///
    /// Not high priority: do not await
    func deleteItem(id: UUID) {
        guard let item = fetchLogItem(id) else {
            debugLog("deleteItem: item \(id) not found — triggering reconciliation")
            remoteDataChanged.send()
            return
        }
        let roll = item.roll
        modelContext.delete(item)
        if let roll {
            roll.cachedExposureCount = max(0, roll.cachedExposureCount - 1)
            recomputeLastExposureDate(for: roll)
            if let camera = roll.camera { syncCameraCache(camera) }
        }
        save()
        ImageCache.shared.evict(id: id)
    }

    /// Persist the new extra exposures count. The VM computes the cycling logic
    /// and updates its local state optimistically.
    ///
    /// Not high priority: do not await
    func setExtraExposures(rollID: UUID, count: Int) {
        guard let roll = fetchRoll(rollID) else {
            debugLog("setExtraExposures: roll \(rollID) not found")
            remoteDataChanged.send()
            return
        }
        roll.extraExposures = count
        if roll.isActive, let camera = roll.camera {
            camera.cachedActiveCapacity = roll.totalCapacity
        }
        save()
    }

    /// Persist a placeholder's new timestamp. The VM has already resorted its local state.
    ///
    /// Not high priority: do not await
    func movePlaceholder(id: UUID, newTimestamp: Date) {
        guard let item = fetchLogItem(id) else {
            debugLog("movePlaceholder: item \(id) not found — triggering reconciliation")
            remoteDataChanged.send()
            return
        }
        item.createdAt = newTimestamp
        save()
    }

    /// Move an item to a different roll. The VM handles this optimistically and fire-and-forgets.
    func moveItem(id: UUID, toRollID: UUID) {
        guard let item = fetchLogItem(id),
              let targetRoll = fetchRoll(toRollID),
              let targetCamera = targetRoll.camera else {
            debugLog("moveItem: item \(id) or roll \(toRollID) not found")
            remoteDataChanged.send()
            return
        }
        let oldRoll = item.roll

        // Re-parent (SwiftData inverse handles the rest)
        item.roll = targetRoll

        // Recompute counts and dates
        if let oldRoll {
            oldRoll.cachedExposureCount = max(0, oldRoll.cachedExposureCount - 1)
            recomputeLastExposureDate(for: oldRoll)
            if let oldCamera = oldRoll.camera { syncCameraCache(oldCamera) }
        }
        targetRoll.cachedExposureCount += 1
        if let date = item.hasRealCreatedAt ? item.createdAt : nil {
            if targetRoll.cachedLastExposureDate == nil || date > targetRoll.cachedLastExposureDate! {
                targetRoll.cachedLastExposureDate = date
            }
        }
        syncCameraCache(targetCamera)

        save()
    }

    // MARK: - Roll API

    /// Persist a new roll. The VM has already added the snapshot optimistically.
    ///
    /// Not high priority: do not await
    func createRoll(id: UUID, cameraID: UUID, filmStock: String, capacity: Int) {
        guard let camera = fetchCamera(cameraID) else {
            debugLog("createRoll: camera \(cameraID) not found — triggering reload to reconcile")
            remoteDataChanged.send()
            return
        }
        // Deactivate any currently active roll on this camera
        for roll in camera.rolls ?? [] where roll.isActive {
            roll.isActive = false
        }
        let roll = Roll(filmStock: filmStock, camera: camera, capacity: capacity)
        roll.id = id
        modelContext.insert(roll)
        syncCameraCache(camera)
        save()
    }

    /// Persist a roll edit. The VM has already updated its local state optimistically.
    ///
    /// Not high priority: do not await
    func editRoll(id: UUID, filmStock: String, capacity: Int) {
        guard let roll = fetchRoll(id) else {
            debugLog("editRoll: roll \(id) not found")
            remoteDataChanged.send()
            return
        }
        roll.filmStock = filmStock
        roll.capacity = capacity
        if let camera = roll.camera { syncCameraCache(camera) }
        save()
    }

    /// Delete a roll and all its exposures (cascade).
    /// The VM has already removed it from its local state optimistically.
    ///
    /// Not high priority: do not await
    func deleteRoll(id: UUID) {
        guard let roll = fetchRoll(id) else {
            debugLog("deleteRoll: roll \(id) not found")
            remoteDataChanged.send()
            return
        }
        let camera = roll.camera
        for item in roll.logItems ?? [] {
            ImageCache.shared.evict(id: item.id)
        }
        modelContext.delete(roll)
        if let camera { syncCameraCache(camera) }
        save()
    }

    // MARK: - Camera API

    /// Persist a new camera. The VM has already added the snapshot optimistically.
    ///
    /// Not high priority: do not await
    func createCamera(id: UUID, name: String, listOrder: Double) {
        let camera = Camera(name: name, listOrder: listOrder)
        camera.id = id
        modelContext.insert(camera)
        save()
    }

    /// Persist a camera rename. The VM has already updated its local state optimistically.
    ///
    /// Not high priority: do not await
    func renameCamera(id: UUID, name: String) {
        guard let camera = fetchCamera(id) else {
            debugLog("renameCamera: camera \(id) not found")
            remoteDataChanged.send()
            return
        }
        camera.name = name
        save()
    }

    /// Delete a camera and all its rolls/exposures (cascade).
    /// The VM has already removed it from its local state optimistically.
    ///
    /// Not high priority: do not await
    func deleteCamera(id: UUID) {
        guard let camera = fetchCamera(id) else {
            debugLog("deleteCamera: camera \(id) not found")
            remoteDataChanged.send()
            return
        }
        // Evict thumbnails for all items in all rolls
        for roll in camera.rolls ?? [] {
            for item in roll.logItems ?? [] {
                ImageCache.shared.evict(id: item.id)
            }
        }
        modelContext.delete(camera)
        save()
    }

    /// Persist a new camera ordering. The VM has already reordered its local state optimistically.
    ///
    /// Not high priority: do not await
    func reorderCameras(orderedIDs: [UUID]) {
        let cameras = (try? modelContext.fetch(FetchDescriptor<Camera>(
            sortBy: [SortDescriptor(\.listOrder)]
        ))) ?? []
        let byID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        // Safety net: append any cameras not in orderedIDs (e.g., arrived via CloudKit during drag)
        let movedSet = Set(orderedIDs)
        let finalOrder = orderedIDs + cameras.map(\.id).filter { !movedSet.contains($0) }
        for (index, id) in finalOrder.enumerated() {
            byID[id]?.listOrder = Double(index)
        }
        save()
    }

    // MARK: - Timezone Change Detection

    private var lastKnownUTCOffset = TimeZone.current.secondsFromGMT()
    private var tzCheckTask: Task<Void, Never>?

    /// Start a 30-second timer that checks for device timezone changes.
    /// If the offset changed, re-publish all observed snapshots with updated formatting.
    func startTimezoneChangeDetection() {
        tzCheckTask = Task(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                let currentOffset = TimeZone.current.secondsFromGMT()
                if currentOffset != lastKnownUTCOffset {
                    debugLog("Device timezone changed: offset \(lastKnownUTCOffset) → \(currentOffset)")
                    lastKnownUTCOffset = currentOffset
                    // Spawn at high priority — this updates the UI
                    Task(priority: .userInitiated) {
                        await self.refreshFormattedSnapshots()
                    }
                }
            }
        }
    }

    /// Called on foreground — check immediately rather than waiting for the timer.
    func checkTimezoneChange() async {
        let currentOffset = TimeZone.current.secondsFromGMT()
        if currentOffset != lastKnownUTCOffset {
            debugLog("Device timezone changed on foreground: offset \(lastKnownUTCOffset) → \(currentOffset)")
            lastKnownUTCOffset = currentOffset
            await refreshFormattedSnapshots()
        }
    }

    /// Signal the VM to re-read all data (formatted strings recomputed by LogItem.snapshot).
    private func refreshFormattedSnapshots() {
        remoteDataChanged.send()
    }

    // MARK: - Remote Changes

    private var remoteChangeObserver: (any NSObjectProtocol)?
    private var maintenanceTask: Task<Void, Never>?

    /// Begin observing CloudKit remote changes. Call once on startup.
    func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task(priority: .userInitiated) { await self.handleRemoteChange() }
        }
    }

    // Cached flat snapshots for diffing remote changes
    private var lastCameras: [CameraSnapshot] = []
    private var lastRolls: [RollSnapshot] = []
    private var lastItems: [LogItemSnapshot] = []

    /// Called on every NSPersistentStoreRemoteChange.
    /// Re-fetches flat snapshots, diffs against cached copies.
    /// Only rebuilds tree and signals the VM if something actually changed.
    private func handleRemoteChange() {
        debugLog("Remote change notification received")

        // Sync caches so snapshots are correct (only saves if something changed)
        syncAllCameraCaches()

        // Re-fetch flat snapshots
        let freshCameras = fetchAllCameraSnapshots()
        let freshRolls = ((try? modelContext.fetch(FetchDescriptor<Roll>())) ?? []).map { $0.snapshot }
        let freshItems = ((try? modelContext.fetch(FetchDescriptor<LogItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).map { $0.snapshot }

        // Diff against cached copies
        let changed = freshCameras != lastCameras || freshRolls != lastRolls || freshItems != lastItems
        guard changed else {
            debugLog("Remote change: no diff, skipping")
            return
        }

        // Update cache
        lastCameras = freshCameras
        lastRolls = freshRolls
        lastItems = freshItems

        // Signal the VM to call loadAll()
        remoteDataChanged.send()

        // --- Debounced: maintenance ---

        maintenanceTask?.cancel()
        maintenanceTask = Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            repairDuplicateActiveRolls()
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
            let keeper = activeRolls
                .sorted { ($0.cachedLastExposureDate ?? .distantPast) > ($1.cachedLastExposureDate ?? .distantPast) }
                .first!
            for roll in activeRolls where roll.id != keeper.id {
                roll.isActive = false
            }
            syncCameraCache(camera)
            didRepair = true
        }
        if didRepair { save() }
    }

    // MARK: - Export

    /// Export all data as JSON. The @concurrent ExportService runs off the actor's executor.
    func exportJSON() async -> URL? {
        let context = ModelContext(modelContainer)
        do {
            return try await ExportService.exportJSON(context: context)
        } catch {
            debugLog("exportJSON failed: \(error)")
            return nil
        }
    }

    /// Export all data as CSV. The @concurrent ExportService runs off the actor's executor.
    func exportCSV() async -> URL? {
        let context = ModelContext(modelContainer)
        do {
            return try await ExportService.exportCSV(context: context)
        } catch {
            debugLog("exportCSV failed: \(error)")
            return nil
        }
    }

    // MARK: - Geocoding

    /// Geocode items missing place names since a cutoff date.
    /// Call on startup (with lastAppLaunchDate cutoff) and foreground (with lastForegroundDate cutoff).
    ///
    /// Not high priority: do not await
    func geocodeItemsIfNeeded(since cutoffDate: Date) async {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> {
                $0.placeName == nil &&
                $0.latitude != nil &&
                $0.longitude != nil &&
                $0.createdAt >= cutoffDate
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        let pending = items.compactMap { item -> (UUID, CLLocation)? in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return (item.id, CLLocation(latitude: lat, longitude: lon))
        }
        let results = await Geocoder.geocodeBatch(pending)
        await applyGeocodingResults(results)
    }

    /// Geocode items missing place names in a specific roll.
    /// Call on roll switch and after remote changes.
    ///
    /// Not high priority: do not await
    func geocodeItemsInRoll(_ rollID: UUID) async {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> {
                $0.roll?.id == rollID &&
                $0.placeName == nil &&
                $0.latitude != nil &&
                $0.longitude != nil
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        let pending = items.compactMap { item -> (UUID, CLLocation)? in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return (item.id, CLLocation(latitude: lat, longitude: lon))
        }
        let results = await Geocoder.geocodeBatch(pending)
        applyGeocodingResults(results)
    }

    /// Core: write geocoding results and signal remote data changed if any items were updated.
    private func applyGeocodingResults(_ results: [(UUID, GeocodingResult)]) {
        guard !results.isEmpty else { return }
        for (id, result) in results {
            if let item = fetchLogItem(id) {
                if let placeName = result.placeName { item.placeName = placeName }
                if let cityName = result.cityName { item.cityName = cityName }
            }
        }
        save()
        debugLog("applyGeocodingResults: updated \(results.count) item(s), sending remoteDataChanged")
        remoteDataChanged.send()
    }

    /// Re-interpolate placeholder timestamps between real exposures.
    /// Repairs precision exhaustion from repeated drag reordering.
    func repairPlaceholderTimestamps(rollID: UUID) {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        guard items.count >= 2, items.contains(where: \.hasRealCreatedAt) else { return }

        var didRepair = false
        var i = 0
        while i < items.count {
            guard !items[i].hasRealCreatedAt else { i += 1; continue }
            let runStart = i
            while i < items.count && !items[i].hasRealCreatedAt { i += 1 }
            let runEnd = i

            let before = runStart > 0
                ? items[runStart - 1].createdAt
                : items[runEnd < items.count ? runEnd : runStart].createdAt.addingTimeInterval(-Double(runEnd - runStart + 1))
            let after = runEnd < items.count
                ? items[runEnd].createdAt
                : before.addingTimeInterval(Double(runEnd - runStart + 1))

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

        if didRepair {
            save()
            debugLog("repairPlaceholderTimestamps: repaired roll \(rollID), sending remoteDataChanged")
            remoteDataChanged.send()
        }
    }

    // MARK: - Maintenance

    /// Periodic cleanup: orphan data, stale cache entries.
    /// Runs every 72h. Fires a detached background task to avoid blocking the actor.
    ///
    /// Not high priority: do not await
    func runPeriodicCleanupIfNeeded() {
        let defaults = UserDefaults.standard
        if let lastClean = defaults.object(forKey: AppSettingsKeys.lastDataCleanDate) as? Date,
           Date().timeIntervalSince(lastClean) < 72 * 60 * 60 { return }

        let previousRollIDs = Set(defaults.stringArray(forKey: AppSettingsKeys.pendingOrphanRollIDs) ?? [])
        let previousItemIDs = Set(defaults.stringArray(forKey: AppSettingsKeys.pendingOrphanItemIDs) ?? [])

        let container = modelContainer
        Task.detached(priority: .background) {
            let context = ModelContext(container)

            // --- 1. Orphan cleanup (two-strike) ---

            let orphanedRolls = (try? context.fetch(FetchDescriptor<Roll>(
                predicate: #Predicate<Roll> { $0.camera == nil }
            ))) ?? []
            let candidateRollIDs = orphanedRolls.map { $0.id.uuidString }

            let orphanedItems = (try? context.fetch(FetchDescriptor<LogItem>(
                predicate: #Predicate<LogItem> { $0.roll == nil }
            ))) ?? []
            let candidateItemIDs = orphanedItems.map { $0.id.uuidString }

            // Persist current candidates for the next run's comparison
            defaults.set(candidateRollIDs, forKey: AppSettingsKeys.pendingOrphanRollIDs)
            defaults.set(candidateItemIDs, forKey: AppSettingsKeys.pendingOrphanItemIDs)

            // Only delete IDs that were also flagged on the previous run
            let confirmedRollIDs = Set(candidateRollIDs).intersection(previousRollIDs)
            let confirmedItemIDs = Set(candidateItemIDs).intersection(previousItemIDs)

            var deletedRolls = 0
            for roll in orphanedRolls where confirmedRollIDs.contains(roll.id.uuidString) {
                for item in roll.logItems ?? [] {
                    ImageCache.shared.evict(id: item.id)
                }
                context.delete(roll)
                deletedRolls += 1
            }
            var deletedItems = 0
            for item in orphanedItems where confirmedItemIDs.contains(item.id.uuidString) {
                ImageCache.shared.evict(id: item.id)
                context.delete(item)
                deletedItems += 1
            }

            if deletedRolls > 0 || deletedItems > 0 {
                debugLog("Orphan cleanup: \(deletedRolls) roll(s), \(deletedItems) item(s)")
                try? context.save()
            }

            // --- 2. Purge stale cache bookkeeper entries ---

            let allRolls = (try? context.fetch(FetchDescriptor<Roll>())) ?? []
            let existingRollIDs = Set(allRolls.map(\.id))
            await ImageCache.shared.bookkeeper.purgeStaleEntries(existingRollIDs: existingRollIDs)

            // --- Done ---

            defaults.set(Date(), forKey: AppSettingsKeys.lastDataCleanDate)
        }
    }

    // MARK: - Internal

    /// Sync cached summary fields on all cameras. Call after remote changes.
    /// Only saves if any cached values actually changed, to avoid triggering a feedback loop
    /// with NSPersistentStoreRemoteChange notifications.
    private func syncAllCameraCaches() {
        let cameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        var didChange = false
        for camera in cameras {
            // Fix roll cached fields while we have them faulted
            for roll in camera.rolls ?? [] {
                let items = roll.logItems ?? []
                let actual = items.count
                if roll.cachedExposureCount != actual {
                    roll.cachedExposureCount = actual
                    didChange = true
                }
                let freshLastDate = items.filter(\.hasRealCreatedAt).map(\.createdAt).max()
                if roll.cachedLastExposureDate != freshLastDate {
                    roll.cachedLastExposureDate = freshLastDate
                    didChange = true
                }
            }
            if syncCameraCache(camera) { didChange = true }
        }
        if didChange { save() }
    }

    /// Update cached summary fields on a camera from its rolls.
    /// Returns true if any value changed.
    @discardableResult
    private func syncCameraCache(_ camera: Camera) -> Bool {
        let rolls = camera.rolls ?? []
        let active = rolls.first(where: \.isActive)
        let newRollCount = rolls.count
        let newTotalExposureCount = rolls.reduce(0) { $0 + $1.cachedExposureCount }
        let newLastUsedDate = rolls.compactMap { $0.cachedLastExposureDate ?? ($0.cachedExposureCount > 0 ? $0.createdAt : nil) }.max()
        let newActiveRollID = active?.id
        let newActiveFilmStock = active?.filmStock
        let newActiveExposureCount = active?.cachedExposureCount
        let newActiveCapacity = active?.totalCapacity

        guard camera.cachedRollCount != newRollCount ||
              camera.cachedTotalExposureCount != newTotalExposureCount ||
              camera.cachedLastUsedDate != newLastUsedDate ||
              camera.cachedActiveRollID != newActiveRollID ||
              camera.cachedActiveFilmStock != newActiveFilmStock ||
              camera.cachedActiveExposureCount != newActiveExposureCount ||
              camera.cachedActiveCapacity != newActiveCapacity
        else { return false }

        camera.cachedRollCount = newRollCount
        camera.cachedTotalExposureCount = newTotalExposureCount
        camera.cachedLastUsedDate = newLastUsedDate
        camera.cachedActiveRollID = newActiveRollID
        camera.cachedActiveFilmStock = newActiveFilmStock
        camera.cachedActiveExposureCount = newActiveExposureCount
        camera.cachedActiveCapacity = newActiveCapacity
        return true
    }

    private func fetchCamera(_ id: UUID) -> Camera? {
        let descriptor = FetchDescriptor<Camera>(predicate: #Predicate { $0.id == id })
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            debugLog("fetchCamera(\(id)) failed: \(error)")
            return nil
        }
    }

    private func fetchAllCameraSnapshots() -> [CameraSnapshot] {
        let descriptor = FetchDescriptor<Camera>(sortBy: [SortDescriptor(\.listOrder)])
        let cameras = (try? modelContext.fetch(descriptor)) ?? []
        return cameras.map { $0.snapshot }
    }


    #if DEBUG
    private func assertOffMain(caller: String = #function) {
        if Thread.isMainThread {
            debugLog("WARNING: DataStore.\(caller) running on main thread")
        }
    }
    private func assertHighPriority(caller: String = #function) {
        assertOffMain(caller: caller)
        let qos = Thread.current.qualityOfService
        if qos != .userInitiated && qos != .userInteractive {
            debugLog("WARNING: DataStore.\(caller) expected high-priority QoS, got \(qos.rawValue)")
        }
    }
    #endif

    private func save() {
        #if DEBUG
        assertOffMain()
        #endif
        do {
            try modelContext.save()
        } catch {
            debugLog("DataStore save failed: \(error)")
        }
    }

    private func fetchRoll(_ id: UUID) -> Roll? {
        let descriptor = FetchDescriptor<Roll>(predicate: #Predicate { $0.id == id })
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            debugLog("fetchRoll(\(id)) failed: \(error)")
            return nil
        }
    }

    private func fetchLogItem(_ id: UUID) -> LogItem? {
        let descriptor = FetchDescriptor<LogItem>(predicate: #Predicate { $0.id == id })
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            debugLog("fetchLogItem(\(id)) failed: \(error)")
            return nil
        }
    }

    private func recomputeLastExposureDate(for roll: Roll) {
        roll.cachedLastExposureDate = (roll.logItems ?? [])
            .filter { $0.hasRealCreatedAt }
            .map(\.createdAt)
            .max()
    }

    private func fetchLogItemIDs(forRoll rollID: UUID) -> [UUID] {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.id)
    }
}
