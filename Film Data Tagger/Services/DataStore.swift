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

struct MoveItemResult: Sendable {
    let targetCameraID: UUID
}

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

    // nonisolated(unsafe): these are let constants and Combine subjects are thread-safe.
    // Safe to subscribe from main actor and send from the DataStore actor.
    nonisolated(unsafe) let rollItemsSubject = CurrentValueSubject<[LogItemSnapshot], Never>([])
    nonisolated(unsafe) let camerasSubject = CurrentValueSubject<[CameraSnapshot], Never>([])
    nonisolated(unsafe) let cameraRollsSubject = CurrentValueSubject<[RollSnapshot], Never>([])
    nonisolated(unsafe) let observedRollInvalidated = PassthroughSubject<Void, Never>()
    nonisolated(unsafe) let observedCameraInvalidated = PassthroughSubject<Void, Never>()

    // MARK: - Observed state

    private var observedRollID: UUID?
    private var observedCameraID: UUID?

    // MARK: - Startup

    /// Provide relationship metadata to the ImageCache bookkeeper so it can decide
    /// which rolls to warm, then fetch item IDs only for those rolls.
    func warmThumbnailCache() async {
        let allCameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let cameraInfo: [(cameraID: UUID, activeRollID: UUID?, rollIDs: [UUID])] = allCameras.map { camera in
            let rolls = camera.rolls ?? []
            let activeRollID = rolls.first(where: \.isActive)?.id
            return (camera.id, activeRollID, rolls.map(\.id))
        }

        // Phase 1: bookkeeper decides which rolls matter
        let bookkeeper = ImageCache.shared.bookkeeper
        await bookkeeper.load()
        let rollsToWarm = await bookkeeper.rollsToWarm(cameraInfo: cameraInfo)

        // Phase 2: fetch item IDs only for those rolls
        var priorityIDs = Set<UUID>()
        for rollID in rollsToWarm {
            let ids = fetchLogItemIDs(forRoll: rollID)
            priorityIDs.formUnion(ids)
        }

        // Phase 3: warm from disk
        await ImageCache.shared.warmOnLaunch(priorityIDs: priorityIDs)
    }

    // MARK: - Read API

    /// Set the actively observed roll. Returns the initial snapshot list
    /// and begins publishing updates for this roll via `rollItemsSubject`.
    /// IMPORTANT: Must return fast — the VM awaits this during navigation transitions.
    /// Deferred work (geocoding, placeholder repair) is fire-and-forget.
    func observeRoll(_ rollID: UUID) async -> [LogItemSnapshot] {
        #if DEBUG
        assertHighPriority()
        #endif
        observedRollID = rollID
        // Fire-and-forget roll access tracking
        let items = await fetchLogItems(forRoll: rollID)
        // Guard against a newer observeRoll call that started during our await
        guard observedRollID == rollID else { return items }
        rollItemsSubject.send(items)
        // Fire-and-forget: geocode + repair placeholders. If either mutates, pushes via subject.
        Task(priority: .utility) {
            await ImageCache.shared.bookkeeper.recordAccess(rollID)
            await self.geocodeItemsInRoll(rollID)
            await self.repairPlaceholderTimestamps(rollID: rollID)
        }
        return items
    }

    /// Stop observing any roll.
    func stopObservingRoll() {
        observedRollID = nil
        rollItemsSubject.send([])
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
            reconcileObservedCamera()
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
            reconcileObservedCamera()
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
    func deleteItem(id: UUID) async {
        guard let item = fetchLogItem(id) else {
            debugLog("deleteItem: item \(id) not found")
            if let rollID = observedRollID {
                rollItemsSubject.send(await fetchLogItems(forRoll: rollID))
            }
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
            reconcileObservedCamera()
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
    func movePlaceholder(id: UUID, newTimestamp: Date) async {
        guard let item = fetchLogItem(id) else {
            debugLog("movePlaceholder: item \(id) not found")
            if let rollID = observedRollID {
                rollItemsSubject.send(await fetchLogItems(forRoll: rollID))
            }
            return
        }
        item.createdAt = newTimestamp
        save()
    }

    /// Move an item to a different roll. NOT optimistic — the VM awaits the result
    /// and then calls `observeRoll` on the target roll.
    ///
    /// Not high priority: do not await
    func moveItem(id: UUID, toRollID: UUID) -> MoveItemResult? {
        guard let item = fetchLogItem(id),
              let targetRoll = fetchRoll(toRollID),
              let targetCamera = targetRoll.camera else {
            debugLog("moveItem: item \(id) or roll \(toRollID) not found")
            reconcileAll()
            return nil
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
        return MoveItemResult(targetCameraID: targetCamera.id)
    }

    // MARK: - Roll API

    /// Set the actively observed camera. Returns its rolls sorted by recency
    /// and begins publishing updates via `cameraRollsSubject`.
    /// IMPORTANT: Must return fast — the VM awaits this during navigation transitions.
    func observeCamera(_ cameraID: UUID) -> [RollSnapshot] {
        observedCameraID = cameraID
        let rolls = fetchRollSnapshots(forCamera: cameraID)
        cameraRollsSubject.send(rolls)
        return rolls
    }

    /// Stop observing any camera's rolls.
    func stopObservingCamera() {
        observedCameraID = nil
        cameraRollsSubject.send([])
    }

    /// Persist a new roll. The VM has already added the snapshot optimistically.
    ///
    /// Not high priority: do not await
    func createRoll(id: UUID, cameraID: UUID, filmStock: String, capacity: Int) {
        guard let camera = fetchCamera(cameraID) else {
            debugLog("createRoll: camera \(cameraID) not found")
            camerasSubject.send(fetchAllCameraSnapshots())
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
            reconcileObservedCamera()
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
            reconcileObservedCamera()
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

    /// Fetch all cameras and publish to `camerasSubject`. Call on startup.
    func loadCameras() {
        #if DEBUG
        assertHighPriority()
        #endif
        camerasSubject.send(fetchAllCameraSnapshots())
    }

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
            camerasSubject.send(fetchAllCameraSnapshots())
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
            camerasSubject.send(fetchAllCameraSnapshots())
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

    /// Immediate: re-fetch observed data and push if changed.
    /// Debounced: expensive maintenance (repair duplicate active rolls).
    private func handleRemoteChange() async {
        debugLog("Remote change notification received")

        // --- Validate: check observed entities still exist ---

        if let cameraID = observedCameraID {
            if fetchCamera(cameraID) == nil {
                debugLog("handleRemoteChange: observed camera \(cameraID) deleted remotely")
                observedCameraID = nil
                cameraRollsSubject.send([])
                observedCameraInvalidated.send()
                // Camera gone → roll under it is gone too
                if observedRollID != nil {
                    observedRollID = nil
                    rollItemsSubject.send([])
                    observedRollInvalidated.send()
                }
            }
        }

        if let rollID = observedRollID {
            if fetchRoll(rollID) == nil {
                debugLog("handleRemoteChange: observed roll \(rollID) deleted remotely")
                observedRollID = nil
                rollItemsSubject.send([])
                observedRollInvalidated.send()
            }
        }

        // --- Immediate: reconcile observed state ---

        if let rollID = observedRollID {
            let fresh = await fetchLogItems(forRoll: rollID)
            if fresh != rollItemsSubject.value {
                rollItemsSubject.send(fresh)
            }
        }

        if let cameraID = observedCameraID {
            let fresh = fetchRollSnapshots(forCamera: cameraID)
            if fresh != cameraRollsSubject.value {
                cameraRollsSubject.send(fresh)
            }
        }

        // Sync all camera caches — remote changes may have added/removed rolls or items
        syncAllCameraCaches()

        // Camera list (always checked)
        let freshCameras = fetchAllCameraSnapshots()
        if freshCameras != camerasSubject.value {
            camerasSubject.send(freshCameras)
        }

        // Geocode any new items in the observed roll that lack place names
        if let rollID = observedRollID {
            await geocodeItemsInRoll(rollID)
        }

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
        await applyGeocodingResults(results)
    }

    /// Core: write geocoding results and push to rollItemsSubject if the observed roll was affected.
    private func applyGeocodingResults(_ results: [(UUID, GeocodingResult)]) async {
        guard !results.isEmpty else { return }
        let affectedIDs = Set(results.map(\.0))
        for (id, result) in results {
            if let item = fetchLogItem(id) {
                if let placeName = result.placeName { item.placeName = placeName }
                if let cityName = result.cityName { item.cityName = cityName }
            }
        }
        save()
        // Push if any geocoded items belong to the observed roll
        if let rollID = observedRollID {
            let currentIDs = Set(rollItemsSubject.value.map(\.id))
            if !affectedIDs.isDisjoint(with: currentIDs) {
                let fresh = await fetchLogItems(forRoll: rollID)
                rollItemsSubject.send(fresh)
            }
        }
    }

    /// Re-interpolate placeholder timestamps between real exposures.
    /// Repairs precision exhaustion from repeated drag reordering.
    /// Pushes updated snapshots via subject if anything changed.
    private func repairPlaceholderTimestamps(rollID: UUID) async {
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
            if observedRollID == rollID {
                let fresh = await fetchLogItems(forRoll: rollID)
                rollItemsSubject.send(fresh)
            }
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
    private func syncAllCameraCaches() {
        let cameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        for camera in cameras {
            // Also fix roll cached fields while we have them faulted
            for roll in camera.rolls ?? [] {
                let items = roll.logItems ?? []
                let actual = items.count
                if roll.cachedExposureCount != actual {
                    roll.cachedExposureCount = actual
                }
                let freshLastDate = items.filter(\.hasRealCreatedAt).map(\.createdAt).max()
                if roll.cachedLastExposureDate != freshLastDate {
                    roll.cachedLastExposureDate = freshLastDate
                }
            }
            syncCameraCache(camera)
        }
        save()
    }

    /// Update cached summary fields on a camera from its rolls.
    /// Call after any write that changes roll count, exposure count, or active roll.
    private func syncCameraCache(_ camera: Camera) {
        let rolls = camera.rolls ?? []
        let active = rolls.first(where: \.isActive)
        camera.cachedRollCount = rolls.count
        camera.cachedTotalExposureCount = rolls.reduce(0) { $0 + $1.cachedExposureCount }
        camera.cachedLastUsedDate = rolls.compactMap { $0.cachedLastExposureDate ?? ($0.cachedExposureCount > 0 ? $0.createdAt : nil) }.max()
        camera.cachedActiveRollID = active?.id
        camera.cachedActiveFilmStock = active?.filmStock
        camera.cachedActiveExposureCount = active?.cachedExposureCount
        camera.cachedActiveCapacity = active?.totalCapacity
    }

    private func fetchCamera(_ id: UUID) -> Camera? {
        let descriptor = FetchDescriptor<Camera>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchAllCameraSnapshots() -> [CameraSnapshot] {
        let descriptor = FetchDescriptor<Camera>(sortBy: [SortDescriptor(\.listOrder)])
        let cameras = (try? modelContext.fetch(descriptor)) ?? []
        return cameras.map { $0.snapshot }
    }

    /// Re-publish rolls for the currently observed camera.
    private func reconcileObservedCamera() {
        if let cameraID = observedCameraID {
            cameraRollsSubject.send(fetchRollSnapshots(forCamera: cameraID))
        }
    }

    /// Re-publish everything: cameras, rolls, and items.
    private func reconcileAll() {
        camerasSubject.send(fetchAllCameraSnapshots())
        reconcileObservedCamera()
        // rollItemsSubject is async (fetchLogItems), so handled separately if needed
    }

    private func fetchRollSnapshots(forCamera cameraID: UUID) -> [RollSnapshot] {
        let descriptor = FetchDescriptor<Roll>(
            predicate: #Predicate<Roll> { $0.camera?.id == cameraID },
            sortBy: [SortDescriptor(\.cachedLastExposureDate, order: .reverse)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map { $0.snapshot }
    }

    #if DEBUG
    private func assertOffMain(caller: String = #function) {
        assert(!Thread.isMainThread, "DataStore.\(caller) must not run on the main thread")
    }
    private func assertHighPriority(caller: String = #function) {
        assertOffMain(caller: caller)
        let qos = Thread.current.qualityOfService
        assert(qos == .userInitiated || qos == .userInteractive,
               "DataStore.\(caller) expected high-priority QoS, got \(qos.rawValue)")
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
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchLogItem(_ id: UUID) -> LogItem? {
        let descriptor = FetchDescriptor<LogItem>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func recomputeLastExposureDate(for roll: Roll) {
        roll.cachedLastExposureDate = (roll.logItems ?? [])
            .filter { $0.hasRealCreatedAt }
            .map(\.createdAt)
            .max()
    }

    private func fetchLogItems(forRoll rollID: UUID) async -> [LogItemSnapshot] {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        // Decode + cache thumbnails on the actor thread (off main)
        for item in items {
            if let data = item.thumbnailData {
                await ImageCache.shared.preload(for: item.id, data: data)
            }
        }
        return items.map { $0.snapshot }
    }

    private func fetchLogItemIDs(forRoll rollID: UUID) -> [UUID] {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.id)
    }
}
