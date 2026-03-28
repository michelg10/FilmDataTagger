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

    let rollItemsSubject = CurrentValueSubject<[LogItemSnapshot], Never>([])

    let camerasSubject = CurrentValueSubject<[CameraSnapshot], Never>([])

    let cameraRollsSubject = CurrentValueSubject<[RollSnapshot], Never>([])

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
    func observeRoll(_ rollID: UUID) async -> [LogItemSnapshot] {
        observedRollID = rollID
        // Fire-and-forget roll access tracking
        Task { await ImageCache.shared.bookkeeper.recordAccess(rollID) }
        let items = await fetchLogItems(forRoll: rollID)
        // Guard against a newer observeRoll call that started during our await
        guard observedRollID == rollID else { return items }
        rollItemsSubject.send(items)
        return items
    }

    /// Stop observing any roll.
    func stopObservingRoll() {
        observedRollID = nil
        rollItemsSubject.send([])
    }

    // MARK: - Write API

    /// Persist a new exposure. The VM has already updated its local state optimistically.
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
        roll.lastExposureDate = createdAt
        roll.exposureCount += 1
        save()
        if let thumbnailData {
            await ImageCache.shared.preload(for: id, data: thumbnailData)
        }
    }

    /// Persist a new placeholder. The VM has already updated its local state optimistically.
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
        roll.exposureCount += 1
        save()
    }

    /// Delete an item. The VM has already removed it from its local state optimistically.
    /// If the item doesn't exist (e.g., already deleted via CloudKit), re-publish
    /// the current roll items so the VM can reconcile.
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
            roll.exposureCount = max(0, roll.exposureCount - 1)
            recomputeLastExposureDate(for: roll)
        }
        save()
        ImageCache.shared.evict(id: id)
    }

    /// Persist the new extra exposures count. The VM computes the cycling logic
    /// and updates its local state optimistically.
    func setExtraExposures(rollID: UUID, count: Int) {
        guard let roll = fetchRoll(rollID) else {
            debugLog("setExtraExposures: roll \(rollID) not found")
            reconcileObservedCamera()
            return
        }
        roll.extraExposures = count
        save()
    }

    /// Persist a placeholder's new timestamp. The VM has already resorted its local state.
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
            oldRoll.exposureCount = max(0, oldRoll.exposureCount - 1)
            recomputeLastExposureDate(for: oldRoll)
        }
        targetRoll.exposureCount += 1
        if let date = item.hasRealCreatedAt ? item.createdAt : nil {
            if targetRoll.lastExposureDate == nil || date > targetRoll.lastExposureDate! {
                targetRoll.lastExposureDate = date
            }
        }

        save()
        return MoveItemResult(targetCameraID: targetCamera.id)
    }

    // MARK: - Roll API

    /// Set the actively observed camera. Returns its rolls sorted by recency
    /// and begins publishing updates via `cameraRollsSubject`.
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
        save()
    }

    /// Persist a roll edit. The VM has already updated its local state optimistically.
    func editRoll(id: UUID, filmStock: String, capacity: Int) {
        guard let roll = fetchRoll(id) else {
            debugLog("editRoll: roll \(id) not found")
            reconcileObservedCamera()
            return
        }
        roll.filmStock = filmStock
        roll.capacity = capacity
        save()
    }

    /// Delete a roll and all its exposures (cascade).
    /// The VM has already removed it from its local state optimistically.
    func deleteRoll(id: UUID) {
        guard let roll = fetchRoll(id) else {
            debugLog("deleteRoll: roll \(id) not found")
            reconcileObservedCamera()
            return
        }
        for item in roll.logItems ?? [] {
            ImageCache.shared.evict(id: item.id)
        }
        modelContext.delete(roll)
        save()
    }

    // MARK: - Camera API

    /// Fetch all cameras and publish to `camerasSubject`. Call on startup.
    func loadCameras() {
        camerasSubject.send(fetchAllCameraSnapshots())
    }

    /// Persist a new camera. The VM has already added the snapshot optimistically.
    func createCamera(id: UUID, name: String, listOrder: Double) {
        let camera = Camera(name: name, listOrder: listOrder)
        camera.id = id
        modelContext.insert(camera)
        save()
    }

    /// Persist a camera rename. The VM has already updated its local state optimistically.
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
    func reorderCameras(orderedIDs: [UUID]) {
        let cameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        for (index, id) in orderedIDs.enumerated() {
            byID[id]?.listOrder = Double(index)
        }
        save()
    }

    // MARK: - Maintenance

    /// Periodic cleanup: orphan data, stale cache entries.
    /// Runs every 72h. Fires a detached background task to avoid blocking the actor.
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
            sortBy: [SortDescriptor(\.lastExposureDate, order: .reverse)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map { $0.snapshot }
    }

    private func save() {
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
        roll.lastExposureDate = (roll.logItems ?? [])
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
